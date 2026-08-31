#!/bin/bash

# Install Docker
curl -fsSL https://get.docker.com | sh

# Add ssm-user to docker group if not exists
id ssm-user &>/dev/null || useradd -m ssm-user
usermod -aG docker ssm-user

# Create directory for Rackula
mkdir -p /opt/rackula

# Create docker-compose.yml for Rackula
cat > /opt/rackula/docker-compose.yml << EOF
services:
  rackula:
    image: ${rackula_image}
    container_name: rackula
    ports:
      - "${rackula_port}:${rackula_port}"
    restart: unless-stopped
EOF

# Start Rackula via docker compose
docker compose -f /opt/rackula/docker-compose.yml up -d

# Wait for Rackula to be ready
sleep 5