package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	token        string
	composePath  string
	serviceLocks sync.Map
)

func getServiceLock(service string) *sync.Mutex {
	val, _ := serviceLocks.LoadOrStore(service, &sync.Mutex{})
	return val.(*sync.Mutex)
}

const networkName = "infra_bite-network"

// deployStrategy selects how a service is deployed. Most services run as
// long-lived containers on this Mac and use zero-downtime blue-green. The
// GPU batch jobs (harvest_post) run on a separate always-off machine and
// require a wake-on-LAN trigger plus a remote rebuild — a fundamentally
// different flow that doesn't fit blue-green.
type deployStrategy string

const (
	strategyBlueGreen      deployStrategy = "blue-green"
	strategyWakeAndRebuild deployStrategy = "wake-and-rebuild"
)

// serviceInfo holds deployment metadata per service.
// - Blue-green services use ContainerName, HealthPort, HealthPath.
// - wake-and-rebuild services use RemoteDeployScript (path relative to
//   Mac host, executed via SSH into host.docker.internal).
type serviceInfo struct {
	Strategy      deployStrategy
	ContainerName string
	HealthPort    int    // internal port for health check (0 = no HTTP check)
	HealthPath    string // e.g. "/actuator/health"
	// RemoteDeployScript is the absolute path to a shell script on the Mac
	// host that performs the deploy. The webhook SSHs in as bite-server and
	// runs `bash <script>`. Only used by wake-and-rebuild strategy.
	RemoteDeployScript string
}

var knownServices = map[string]serviceInfo{
	"bite-api":     {Strategy: strategyBlueGreen, ContainerName: "bite-api", HealthPort: 8080, HealthPath: "/actuator/health"},
	"recsys-api":   {Strategy: strategyBlueGreen, ContainerName: "bite-recsys", HealthPort: 8001, HealthPath: "/health"},
	"bite-web":     {Strategy: strategyBlueGreen, ContainerName: "bite-web", HealthPort: 3000, HealthPath: ""},
	"bite-web-dev": {Strategy: strategyBlueGreen, ContainerName: "bite-web-dev", HealthPort: 3000, HealthPath: ""},
	"bite-api-dev": {Strategy: strategyBlueGreen, ContainerName: "bite-api-dev", HealthPort: 8080, HealthPath: "/actuator/health"},
	"harvester-go": {Strategy: strategyBlueGreen, ContainerName: "bite-harvester", HealthPort: 0, HealthPath: ""},
	"recommender":  {Strategy: strategyBlueGreen, ContainerName: "bite-recommender", HealthPort: 0, HealthPath: ""},
	"harvest-post": {
		Strategy:           strategyWakeAndRebuild,
		RemoteDeployScript: "/Users/bite-server/projects/infra/scripts/deploy-gpu-harvest-post.sh",
	},
	"bite-monitor": {Strategy: strategyBlueGreen, ContainerName: "bite-monitor", HealthPort: 3000, HealthPath: ""},
	"bite-metric":  {Strategy: strategyBlueGreen, ContainerName: "bite-metric", HealthPort: 3000, HealthPath: ""},
}

// composeConfig is a minimal representation of `docker compose config --format json`.
type composeConfig struct {
	Services map[string]composeService     `json:"services"`
	Volumes  map[string]composeNamedVolume `json:"volumes"`
}

type composeNamedVolume struct {
	Name string `json:"name"`
}

type composeService struct {
	Image       string              `json:"image"`
	Environment json.RawMessage     `json:"environment"`
	EnvFile     json.RawMessage     `json:"env_file"`
	Volumes     []composeVolume     `json:"volumes"`
	Healthcheck *composeHealthcheck `json:"healthcheck"`
	Restart     string              `json:"restart"`
}

type composeVolume struct {
	Type     string `json:"type"`
	Source   string `json:"source"`
	Target   string `json:"target"`
	ReadOnly bool   `json:"read_only"`
}

type composeHealthcheck struct {
	Test        []string `json:"test"`
	Interval    string   `json:"interval"`
	Timeout     string   `json:"timeout"`
	Retries     int      `json:"retries"`
	StartPeriod string   `json:"start_period"`
	Disable     bool     `json:"disable"`
}

// resolvedConfig is the post-processed view we hand to the deploy step.
// Named volumes are already mapped to their project-prefixed Docker names.
type resolvedConfig struct {
	Image       string
	Env         map[string]string
	HasEnvFile  bool
	Volumes     []composeVolume
	Healthcheck *composeHealthcheck
	Restart     string
}

type apiResponse struct {
	OK      bool   `json:"ok"`
	Message string `json:"message,omitempty"`
	Output  string `json:"output,omitempty"`
}

func main() {
	token = os.Getenv("DEPLOY_TOKEN")
	if token == "" {
		log.Fatal("DEPLOY_TOKEN is required")
	}

	composePath = os.Getenv("COMPOSE_PATH")
	if composePath == "" {
		composePath = "/infra"
	}

	http.HandleFunc("/deploy", handleDeploy)
	http.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		json.NewEncoder(w).Encode(apiResponse{OK: true, Message: "healthy"})
	})

	log.Println("deploy-webhook listening on :9000")
	log.Fatal(http.ListenAndServe(":9000", nil))
}

func handleDeploy(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(apiResponse{OK: false, Message: "POST only"})
		return
	}

	if r.Header.Get("Authorization") != "Bearer "+token {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(apiResponse{OK: false, Message: "unauthorized"})
		return
	}

	service := strings.TrimSpace(r.URL.Query().Get("service"))
	info, ok := knownServices[service]
	if !ok || service == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(apiResponse{OK: false, Message: fmt.Sprintf("unknown service: %s", service)})
		return
	}

	svcMu := getServiceLock(service)
	svcMu.Lock()
	defer svcMu.Unlock()

	var (
		output string
		err    error
	)
	switch info.Strategy {
	case strategyBlueGreen, "": // legacy entries default to blue-green
		output, err = blueGreenDeploy(service, info)
	case strategyWakeAndRebuild:
		output, err = wakeAndRebuild(service, info)
	default:
		err = fmt.Errorf("unknown strategy %q for service %s", info.Strategy, service)
	}

	if err != nil {
		log.Printf("deploy failed service=%s err=%v", service, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(apiResponse{OK: false, Message: err.Error(), Output: output})
		return
	}

	log.Printf("deploy succeeded service=%s", service)
	json.NewEncoder(w).Encode(apiResponse{OK: true, Message: "deployed", Output: output})
}

// wakeAndRebuild handles services that run on the GPU machine, which is
// normally powered off. It SSHs from the webhook container to the Mac host
// (via host.docker.internal, which Colima exposes as the VM gateway) and
// runs the service-specific deploy script. The script is responsible for:
//
//   1. Sending wake-on-LAN to the GPU
//   2. Waiting for the GPU's SSH to become reachable
//   3. Running `git pull` + `docker compose build` on the GPU
//
// Putting the orchestration in a host-side script keeps the complex SSH
// chain (webhook → Mac → GPU) and host-only tools (wakeonlan, Mac's
// ~/.ssh/id_ed25519 that the GPU trusts) out of this container.
//
// The SSH key used from the webhook container → Mac is the
// github-actions-deploy ed25519 key, mounted read-only at
// /root/.ssh/deploy_ed25519 by docker-compose.yml.
func wakeAndRebuild(service string, info serviceInfo) (string, error) {
	if info.RemoteDeployScript == "" {
		return "", fmt.Errorf("service %s has no RemoteDeployScript", service)
	}

	cmd := exec.Command(
		"ssh",
		"-i", "/root/.ssh/deploy_ed25519",
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "ConnectTimeout=10",
		"-o", "BatchMode=yes",
		"-o", "UserKnownHostsFile=/root/.ssh/known_hosts",
		"bite-server@host.docker.internal",
		"bash "+info.RemoteDeployScript,
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("remote deploy script failed: %w", err)
	}
	return string(out), nil
}

// blueGreenDeploy performs a zero-downtime deploy:
//  1. Pull latest image
//  2. Resolve image name + env vars from compose config
//  3. Start green container on the same network with matching DNS alias
//  4. Health-check the green container
//  5. Stop the old (blue) container — green is already serving traffic via the alias
//  6. Rename green to the original container name
func blueGreenDeploy(service string, info serviceInfo) (string, error) {
	var logs strings.Builder
	logf := func(format string, args ...any) {
		msg := fmt.Sprintf(format, args...)
		log.Print(msg)
		logs.WriteString(msg + "\n")
	}

	greenName := info.ContainerName + "-green"

	// --- 1. Pull latest image ---
	logf("[1/6] pulling image for %s", service)
	out, err := run(composePath, "docker", "compose", "pull", service)
	logs.WriteString(out)
	if err != nil {
		return logs.String(), fmt.Errorf("pull failed: %w", err)
	}

	// --- 2. Resolve image and environment from compose ---
	logf("[2/6] resolving compose config")
	cfg, err := resolveServiceConfig(service)
	if err != nil {
		return logs.String(), fmt.Errorf("config resolution failed: %w", err)
	}
	logf("  image=%s envVars=%d envFile=%v volumes=%d healthcheck=%v",
		cfg.Image, len(cfg.Env), cfg.HasEnvFile, len(cfg.Volumes), cfg.Healthcheck != nil)

	// --- 3. Cleanup stale green container (if any) ---
	run("", "docker", "rm", "-f", greenName)

	// --- 4. Start green container ---
	//
	// Host port bindings from compose are intentionally NOT applied here:
	// blue-green requires green to coexist with blue, so the same host port
	// cannot be claimed twice. All inter-service traffic (cloudflared, the
	// monitor, etc.) goes through bite-network DNS, so dropping host ports
	// is fine in production. For direct host-side debug access, run
	// `docker compose up -d --force-recreate <service>` manually.
	logf("[3/6] starting green container: %s", greenName)
	restart := cfg.Restart
	if restart == "" {
		restart = "unless-stopped"
	}
	args := []string{
		"run", "-d",
		"--name", greenName,
		"--network", networkName,
		"--network-alias", service, // shares DNS name with the blue container
		"--restart", restart,
	}
	if cfg.HasEnvFile {
		args = append(args, "--env-file", composePath+"/.env")
	}
	for k, v := range cfg.Env {
		args = append(args, "-e", k+"="+v)
	}
	for _, v := range cfg.Volumes {
		if spec := buildMountSpec(v); spec != "" {
			args = append(args, "--mount", spec)
		}
	}
	args = append(args, buildHealthArgs(cfg.Healthcheck)...)
	args = append(args, cfg.Image)

	out, err = run("", "docker", args...)
	logs.WriteString(out)
	if err != nil {
		run("", "docker", "rm", "-f", greenName)
		return logs.String(), fmt.Errorf("green start failed: %w", err)
	}

	// --- 5. Health check ---
	logf("[4/6] health checking green container")
	if err := healthCheck(greenName, info); err != nil {
		logf("  health check FAILED — rolling back")
		dumpLogs := runQuiet("docker", "logs", "--tail", "30", greenName)
		logs.WriteString("--- green container logs ---\n" + dumpLogs + "\n")
		run("", "docker", "rm", "-f", greenName)
		return logs.String(), fmt.Errorf("health check failed: %w", err)
	}
	logf("  health check passed")

	// --- 6. Swap: stop blue, rename green ---
	logf("[5/6] stopping old container: %s", info.ContainerName)
	run("", "docker", "stop", "-t", "10", info.ContainerName)
	run("", "docker", "rm", info.ContainerName)

	logf("[6/6] renaming %s -> %s", greenName, info.ContainerName)
	out, err = run("", "docker", "rename", greenName, info.ContainerName)
	if err != nil {
		logs.WriteString(out)
		return logs.String(), fmt.Errorf("rename failed: %w", err)
	}

	logf("deploy complete: %s", service)
	return logs.String(), nil
}

// resolveServiceConfig uses `docker compose config` to get the fully-resolved
// view of a service. Named volume references are mapped to their
// project-prefixed Docker names so the resulting `docker run` finds them.
func resolveServiceConfig(service string) (resolvedConfig, error) {
	out, err := run(composePath, "docker", "compose", "--profile", "batch", "config", "--format", "json")
	if err != nil {
		return resolvedConfig{}, fmt.Errorf("compose config: %w (%s)", err, out)
	}

	var cfg composeConfig
	if err := json.Unmarshal([]byte(out), &cfg); err != nil {
		return resolvedConfig{}, fmt.Errorf("parse config: %w", err)
	}

	svc, ok := cfg.Services[service]
	if !ok {
		return resolvedConfig{}, fmt.Errorf("service %q not in compose config", service)
	}

	volumes := make([]composeVolume, 0, len(svc.Volumes))
	for _, v := range svc.Volumes {
		if v.Type == "volume" {
			if named, ok := cfg.Volumes[v.Source]; ok && named.Name != "" {
				v.Source = named.Name
			}
		}
		volumes = append(volumes, v)
	}

	return resolvedConfig{
		Image:       svc.Image,
		Env:         parseEnv(svc.Environment),
		HasEnvFile:  svc.EnvFile != nil && string(svc.EnvFile) != "null",
		Volumes:     volumes,
		Healthcheck: svc.Healthcheck,
		Restart:     svc.Restart,
	}, nil
}

// parseEnv handles both map {"K":"V"} and list ["K=V"] formats.
func parseEnv(raw json.RawMessage) map[string]string {
	if raw == nil || string(raw) == "null" {
		return nil
	}

	// Try map format: {"KEY": "VALUE", ...}
	var m map[string]interface{}
	if err := json.Unmarshal(raw, &m); err == nil {
		result := make(map[string]string, len(m))
		for k, v := range m {
			result[k] = fmt.Sprintf("%v", v)
		}
		return result
	}

	// Try list format: ["KEY=VALUE", ...]
	var list []string
	if err := json.Unmarshal(raw, &list); err == nil {
		result := make(map[string]string, len(list))
		for _, entry := range list {
			if k, v, ok := strings.Cut(entry, "="); ok {
				result[k] = v
			}
		}
		return result
	}

	return nil
}

// healthCheck waits for the green container to become healthy.
func healthCheck(containerName string, info serviceInfo) error {
	if info.HealthPath != "" && info.HealthPort > 0 {
		return httpHealthCheck(containerName, info.HealthPort, info.HealthPath, 90*time.Second)
	}
	// No HTTP health endpoint — wait briefly and verify container is still running.
	time.Sleep(5 * time.Second)
	out := runQuiet("docker", "inspect", "-f", "{{.State.Running}}", containerName)
	if strings.TrimSpace(out) != "true" {
		return fmt.Errorf("container exited shortly after start")
	}
	return nil
}

func httpHealthCheck(host string, port int, path string, timeout time.Duration) error {
	url := fmt.Sprintf("http://%s:%d%s", host, port, path)
	client := &http.Client{Timeout: 3 * time.Second}
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		resp, err := client.Get(url)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 400 {
				return nil
			}
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timed out after %s waiting for %s", timeout, url)
}

func run(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	if dir != "" {
		cmd.Dir = dir
	}
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func runQuiet(name string, args ...string) string {
	out, _ := exec.Command(name, args...).CombinedOutput()
	return string(out)
}

// buildMountSpec turns a compose volume entry into a `docker run --mount`
// string. Returns "" for entries we can't represent (missing fields,
// unsupported type) so the caller can skip them.
func buildMountSpec(v composeVolume) string {
	if v.Target == "" {
		return ""
	}
	var parts []string
	switch v.Type {
	case "bind", "volume":
		if v.Source == "" {
			return ""
		}
		parts = []string{"type=" + v.Type, "source=" + v.Source, "destination=" + v.Target}
	case "tmpfs":
		parts = []string{"type=tmpfs", "destination=" + v.Target}
	default:
		return ""
	}
	if v.ReadOnly {
		parts = append(parts, "readonly")
	}
	return strings.Join(parts, ",")
}

// buildHealthArgs translates a compose healthcheck block into the
// `docker run --health-*` flags. Returns nil if the healthcheck is absent,
// disabled, or doesn't produce a usable command.
func buildHealthArgs(hc *composeHealthcheck) []string {
	if hc == nil || hc.Disable {
		return nil
	}
	cmd := buildHealthCmd(hc.Test)
	if cmd == "" {
		return nil
	}
	args := []string{"--health-cmd", cmd}
	if hc.Interval != "" {
		args = append(args, "--health-interval", hc.Interval)
	}
	if hc.Timeout != "" {
		args = append(args, "--health-timeout", hc.Timeout)
	}
	if hc.Retries > 0 {
		args = append(args, "--health-retries", strconv.Itoa(hc.Retries))
	}
	if hc.StartPeriod != "" {
		args = append(args, "--health-start-period", hc.StartPeriod)
	}
	return args
}

// buildHealthCmd flattens compose's healthcheck.test list into a single
// shell string, matching `docker run --health-cmd` semantics (the value is
// always run via `/bin/sh -c`). Returns "" for NONE / empty / unrecognized.
func buildHealthCmd(test []string) string {
	if len(test) == 0 {
		return ""
	}
	switch test[0] {
	case "NONE":
		return ""
	case "CMD-SHELL":
		if len(test) >= 2 {
			return test[1]
		}
		return ""
	case "CMD":
		return joinShellQuoted(test[1:])
	default:
		return joinShellQuoted(test)
	}
}

func joinShellQuoted(args []string) string {
	quoted := make([]string, len(args))
	for i, s := range args {
		quoted[i] = shellQuote(s)
	}
	return strings.Join(quoted, " ")
}

// shellQuote wraps s in single quotes if it contains anything outside a
// safe POSIX-shell-portable set, escaping embedded single quotes.
func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	for _, r := range s {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') ||
			r == '_' || r == '-' || r == '/' || r == '.' || r == ':' || r == '=' || r == '+' || r == '@' || r == ',') {
			return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
		}
	}
	return s
}
