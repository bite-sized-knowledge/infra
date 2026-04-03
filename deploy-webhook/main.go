package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

var (
	token       string
	composePath string
	mu          sync.Mutex
)

const networkName = "infra_bite-network"

// serviceInfo holds blue-green deployment metadata per service.
type serviceInfo struct {
	ContainerName string
	HealthPort    int    // internal port for health check (0 = no HTTP check)
	HealthPath    string // e.g. "/actuator/health"
}

var knownServices = map[string]serviceInfo{
	"bite-api":     {ContainerName: "bite-api", HealthPort: 8080, HealthPath: "/actuator/health"},
	"recsys-api":   {ContainerName: "bite-recsys", HealthPort: 8001, HealthPath: "/health"},
	"bite-web":     {ContainerName: "bite-web", HealthPort: 3000, HealthPath: ""},
	"bite-web-dev": {ContainerName: "bite-web-dev", HealthPort: 3000, HealthPath: ""},
	"bite-api-dev": {ContainerName: "bite-api-dev", HealthPort: 8080, HealthPath: "/actuator/health"},
	"harvester-go": {ContainerName: "bite-harvester", HealthPort: 0, HealthPath: ""},
	"recommender":  {ContainerName: "bite-recommender", HealthPort: 0, HealthPath: ""},
}

// composeConfig is a minimal representation of `docker compose config --format json`.
type composeConfig struct {
	Services map[string]composeService `json:"services"`
}

type composeService struct {
	Image       string          `json:"image"`
	Environment json.RawMessage `json:"environment"`
	EnvFile     json.RawMessage `json:"env_file"`
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

	mu.Lock()
	defer mu.Unlock()

	output, err := blueGreenDeploy(service, info)
	if err != nil {
		log.Printf("deploy failed service=%s err=%v", service, err)
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(apiResponse{OK: false, Message: err.Error(), Output: output})
		return
	}

	log.Printf("deploy succeeded service=%s", service)
	json.NewEncoder(w).Encode(apiResponse{OK: true, Message: "deployed", Output: output})
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
	image, envVars, hasEnvFile, err := resolveServiceConfig(service)
	if err != nil {
		return logs.String(), fmt.Errorf("config resolution failed: %w", err)
	}
	logf("  image=%s envVars=%d envFile=%v", image, len(envVars), hasEnvFile)

	// --- 3. Cleanup stale green container (if any) ---
	run("", "docker", "rm", "-f", greenName)

	// --- 4. Start green container ---
	logf("[3/6] starting green container: %s", greenName)
	args := []string{
		"run", "-d",
		"--name", greenName,
		"--network", networkName,
		"--network-alias", service, // shares DNS name with the blue container
		"--restart", "unless-stopped",
	}
	if hasEnvFile {
		args = append(args, "--env-file", composePath+"/.env")
	}
	for k, v := range envVars {
		args = append(args, "-e", k+"="+v)
	}
	args = append(args, image)

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
// image name and environment variables for a service.
func resolveServiceConfig(service string) (image string, env map[string]string, hasEnvFile bool, err error) {
	out, err := run(composePath, "docker", "compose", "config", "--format", "json")
	if err != nil {
		return "", nil, false, fmt.Errorf("compose config: %w (%s)", err, out)
	}

	var cfg composeConfig
	if err := json.Unmarshal([]byte(out), &cfg); err != nil {
		return "", nil, false, fmt.Errorf("parse config: %w", err)
	}

	svc, ok := cfg.Services[service]
	if !ok {
		return "", nil, false, fmt.Errorf("service %q not in compose config", service)
	}

	env = parseEnv(svc.Environment)
	hasEnvFile = svc.EnvFile != nil && string(svc.EnvFile) != "null"

	return svc.Image, env, hasEnvFile, nil
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
