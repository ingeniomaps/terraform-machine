#!/bin/bash
set -euo pipefail

# Health check cada 30 segundos
while true; do
  sleep 30
  if ! curl -f http://localhost:${health_check_port}${health_check_path} > /dev/null 2>&1; then
    echo "Health check failed, restarting container..."
    docker restart $(docker ps -q --filter ancestor=${image_full_path}) || true
  fi
done &

