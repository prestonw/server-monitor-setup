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

# Update the package list
echo "Updating package list..."
sudo apt-get update -qq

# Install required packages with a progress bar
echo "Installing required packages..."
{
    sudo apt-get install -y golang-go caddy tailscale shellinabox
} & show_progress $!

# Enable and start Tailscale, with interactive setup
echo "Starting Tailscale setup..."
sudo tailscale up

# Download and install Go web application
echo "Setting up Go web application..."
mkdir -p ~/go/src/monitor
cd ~/go/src/monitor

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

# Build the Go application
echo "Building Go application..."
go build -o server main.go

# Run the Go application in the background
echo "Running Go application..."
nohup ./server &

# Create Caddyfile
echo "Configuring Caddy..."
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOL
:80 {
    reverse_proxy /metrics localhost:8080
}
EOL

# Run Caddy with the Caddyfile
echo "Starting Caddy server..."
sudo caddy run --config /etc/caddy/Caddyfile &

# Output the server address
tailscale_ip=$(tailscale ip -4)
echo "Setup complete. Access your server metrics at http://$tailscale_ip:80/metrics"
