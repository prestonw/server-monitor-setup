#!/bin/bash

# Update the package list
sudo apt-get update

# Install required packages
sudo apt-get install -y golang-go caddy tailscale shellinabox

# Enable and start Tailscale
sudo tailscale up

# Download and install Go web application
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
go build -o server main.go

# Run the Go application in the background
nohup ./server &

# Create Caddyfile
sudo cat <<EOL > /etc/caddy/Caddyfile
:80 {
    reverse_proxy /metrics localhost:8080
}
EOL

# Run Caddy with the Caddyfile
sudo caddy run --config /etc/caddy/Caddyfile

# Output the server address
tailscale ip -4
echo "Setup complete. Access your server metrics at http://$(tailscale ip -4):80/metrics"
