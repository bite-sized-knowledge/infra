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
)

var (
	token       string
	composePath string
	mu          sync.Mutex
)

// Allowed service names to prevent arbitrary command injection
var allowedServices = map[string]bool{
	"bite-api":     true,
	"recsys-api":   true,
	"harvester-go": true,
	"recommender":  true,
	"bite-web":     true,
	"bite-web-dev": true,
	"bite-api-dev": true,
}

type response struct {
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
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(response{OK: true, Message: "healthy"})
	})

	log.Println("deploy-webhook listening on :9000")
	log.Fatal(http.ListenAndServe(":9000", nil))
}

func handleDeploy(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(response{OK: false, Message: "POST only"})
		return
	}

	auth := r.Header.Get("Authorization")
	if auth != "Bearer "+token {
		w.WriteHeader(http.StatusUnauthorized)
		json.NewEncoder(w).Encode(response{OK: false, Message: "unauthorized"})
		return
	}

	service := strings.TrimSpace(r.URL.Query().Get("service"))
	if service == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(response{OK: false, Message: "service parameter required"})
		return
	}

	if !allowedServices[service] {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(response{OK: false, Message: fmt.Sprintf("unknown service: %s", service)})
		return
	}

	mu.Lock()
	defer mu.Unlock()

	log.Printf("deploying service=%s", service)

	pullCmd := exec.Command("docker", "compose", "pull", service)
	pullCmd.Dir = composePath
	pullOut, err := pullCmd.CombinedOutput()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(response{OK: false, Message: "pull failed", Output: string(pullOut)})
		return
	}

	upCmd := exec.Command("docker", "compose", "up", "-d", service)
	upCmd.Dir = composePath
	upOut, err := upCmd.CombinedOutput()
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(response{OK: false, Message: "up failed", Output: string(upOut)})
		return
	}

	combined := string(pullOut) + string(upOut)
	log.Printf("deployed service=%s successfully", service)
	json.NewEncoder(w).Encode(response{OK: true, Message: "deployed", Output: combined})
}
