#!/bin/bash

# Log file
LOGFILE="/tmp/setup.log"

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOGFILE
}

log "Script started"

# Check if the script is running at all
log "This is a test log to ensure the script is running."

# Update the package list
log "Updating package list..."
sudo apt-get update -qq
if [ $? -eq 0 ]; then
    log "Package list updated successfully"
else
    log "Failed to update package list"
    exit 1
fi

# Install required packages with a progress bar
log "Installing required packages..."
sudo apt-get install -y golang-go caddy tailscale shellinabox
if [ $? -eq 0 ]; then
    log "Packages installed successfully"
else
    log "Failed to install required packages"
    exit 1
fi

# Enable and start Tailscale, with interactive setup
log "Starting Tailscale setup..."
sudo tailscale up
if [ $? -eq 0 ]; then
    log "Tailscale started successfully"
else
    log "Failed to start Tailscale"
    exit 1
fi

# Download and install Go web application
log "Setting up Go web application..."
mkdir -p ~/go/src/monitor
if [ $? -eq 0 ]; then
    log "Go source directory created"
else
    log "Failed to create Go source directory"
    exit 1
fi

cd ~/go/src/monitor
if [ $? -eq 0 ]; then
    log "Changed directory to Go source"
else
    log "Failed to change directory to Go source"
    exit 1
fi

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
if [ $? -eq 0 ]; then
    log "Go application source code written"
else
    log "Failed to write Go application source code"
    exit 1
fi

log "Building Go application..."
go build -o server main.go
if [ $? -eq 0 ]; then
    log "Go application built successfully"
else
    log "Failed to build Go application"
    exit 1
fi

log "Running Go application..."
nohup ./server &
if [ $? -eq 0 ]; then
    log "Go application started"
else
    log "Failed to start Go application"
    exit 1
fi

log "Configuring Caddy..."
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOL
:80 {
    reverse_proxy /metrics localhost:8080
}
EOL
if [ $? -eq 0 ]; then
    log "Caddyfile configured"
else
    log "Failed to configure Caddyfile"
    exit 1
fi

log "Starting Caddy server..."
sudo caddy run --config /etc/caddy/Caddyfile &
if [ $? -eq 0 ]; then
    log "Caddy server started"
else
    log "Failed to start Caddy server"
    exit 1
fi

# Output the server address
tailscale_ip=$(tailscale ip -4)
if [ $? -eq 0 ]; then
    log "Setup complete. Access your server metrics at http://$tailscale_ip:80/metrics"
else
    log "Failed to get Tailscale IP"
    exit 1
fi

log "Script finished"
