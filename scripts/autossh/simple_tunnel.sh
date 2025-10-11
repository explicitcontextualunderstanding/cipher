#!/bin/bash
# Simple script to maintain SSH reverse tunnel for Cipher MCP access

USER="amazon1148"
HOST="192.168.1.86"
REMOTE_PORT="3001"
LOCAL_PORT="3000"
LOGFILE="$HOME/Library/Logs/cipher-ssh-tunnel.log"

mkdir -p "$(dirname "$LOGFILE")"

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Function to start tunnel
start_tunnel() {
    log "Starting SSH reverse tunnel: $HOST:$REMOTE_PORT -> localhost:$LOCAL_PORT"

    while true; do
        log "Establishing SSH tunnel..."

        ssh -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o StrictHostKeyChecking=accept-new \
            -N -R 127.0.0.1:$REMOTE_PORT:127.0.0.1:$LOCAL_PORT \
            $USER@$HOST

        log "SSH tunnel disconnected, waiting 10 seconds before reconnect..."
        sleep 10
    done
}

# Kill any existing tunnels
pkill -f "ssh.*-R.*$REMOTE_PORT" 2>/dev/null || true

# Start the tunnel
start_tunnel