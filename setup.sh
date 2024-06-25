#!/bin/bash

# Log file
LOGFILE="/tmp/setup.log"

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOGFILE
}

log "Script started"

# Check DNS resolution
log "Checking DNS resolution..."
if ! nslookup google.com > /dev/null; then
    log "DNS resolution failed. Please check your network configuration."
    exit 1
else
    log "DNS resolution succeeded."
fi

# Check internet connectivity
log "Checking internet connectivity..."
if ! ping -c 4 8.8.8.8 > /dev/null; then
    log "Internet connectivity check failed. Please check your network connection."
    exit 1
else
    log "Internet connectivity check succeeded."
fi

# Check DNS resolution and connectivity to GitHub
log "Checking connectivity to GitHub..."
if ! ping -c 4 github.com > /dev/null; then
    log "Unable to reach GitHub. Please check your DNS settings or internet connectivity."
    log "To resolve this issue, ensure that your DNS server is properly configured in /etc/resolv.conf."
    log "You can manually set the DNS server by adding the following lines to /etc/resolv.conf:"
    log "nameserver 8.8.8.8"
    log "nameserver 8.8.4.4"
    exit 1
else
    log "Successfully reached GitHub."
fi

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

# Enable and start Tailscale, with specific settings to keep local network access
log "Starting Tailscale setup..."
sudo tailscale up --accept-routes --advertise-exit-node=false --advertise-routes=<local-network-range>
if [ $? -eq 0 ]; then
    log "Tailscale started successfully with local network access maintained"
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

log "Stopping any running Go application..."
pkill server

log "Running Go application..."
nohup ./server > nohup.out 2>&1 &
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

log "Stopping any running Caddy server..."
sudo pkill caddy

log "Starting Caddy server..."
sudo caddy run --config /etc/caddy/Caddyfile > caddy.log 2>&1 &
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
