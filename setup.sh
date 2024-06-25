#!/bin/bash

# Function to display a progress bar
show_progress() {
    echo -ne "Installing packages: ["
    while kill -0 $1 2> /dev/null; do
        echo -ne "#"
        sleep 1
    done
    echo -ne "]\n"
}

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Update the package list
log "Updating package list..."
sudo apt-get update -qq || { log "Failed to update package list"; exit 1; }

# Install required packages with a progress bar
log "Installing required packages..."
{
    sudo apt-get install -y golang-go caddy tailscale shellinabox
} & show_progress $!
wait $! || { log "Failed to install required packages"; exit 1; }

# Enable and start Tailscale, with interactive setup
log "Starting Tailscale setup..."
sudo tailscale up || { log "Failed to start Tailscale"; exit 1; }

# Download and install Go web application
log "Setting up Go web application..."
mkdir -p ~/go/src/monitor || { log "Failed to create Go source directory"; exit 1; }
cd ~/go/src/monitor || { log "Failed to change directory to Go source"; exit 1; }

log "Writing Go application source code..."
cat <<EOL > main.go
package main

import (
    "fmt"
    "net/http"
    "os/exec"
    "runtime"
)

func getMetrics() string {
    cmd := exec.Command("htop", "-n", "1")
    out, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Sprintf("Error: %s", err)
    }
    return string(out)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    metrics := getMetrics()
    fmt.Fprintf(w, "<pre>%s</pre>", metrics)
}

func main() {
    http.HandleFunc("/metrics", metricsHandler)
    port := "8080"
    if runtime.GOOS == "windows" {
        port = "8000"
    }
    fmt.Printf("Server running at http://localhost:%s/metrics\n", port)
    http.ListenAndServe(":"+port, nil)
}
EOL

log "Building Go application..."
go build -o server main.go || { log "Failed to build Go application"; exit 1; }

log "Running Go application..."
nohup ./server & || { log "Failed to start Go application"; exit 1; }

log "Configuring Caddy..."
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOL
:80 {
    reverse_proxy /metrics localhost:8080
}
EOL

log "Starting Caddy server..."
sudo caddy run --config /etc/caddy/Caddyfile & || { log "Failed to start Caddy server"; exit 1; }

# Output the server address
tailscale_ip=$(tailscale ip -4) || { log "Failed to get Tailscale IP"; exit 1; }
log "Setup complete. Access your server metrics at http://$tailscale_ip:80/metrics"
