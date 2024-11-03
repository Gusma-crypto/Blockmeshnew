#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "-----------------------------------------------------"
    case $level in
        "INFO") echo -e "${CYAN}[INFO] ${timestamp} - ${message}${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS] ${timestamp} - ${message}${NC}" ;;
        "ERROR") echo -e "${RED}[ERROR] ${timestamp} - ${message}${NC}" ;;
    esac
    echo -e "-----------------------------------------------------\n"
}

cleanup() {
    rm -f blockmesh-cli.tar.gz
}
trap cleanup EXIT

log "INFO" "Starting Docker and BlockMesh CLI Setup..."
sleep 2

DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)"
BLOCKMESH_API_URL="https://api.github.com/repos/block-mesh/block-mesh-monorepo/releases/latest"

log "INFO" "Updating package list and installing base packages..."
sudo apt update && sudo apt upgrade -y

if ! command -v docker &> /dev/null; then
    log "INFO" "Installing Docker..."
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    curl -fsSL $DOCKER_GPG_URL | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
else
    log "SUCCESS" "Docker is already installed, skipping..."
fi

log "INFO" "Installing Docker Compose..."
sudo curl -L $DOCKER_COMPOSE_URL -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
log "SUCCESS" "Docker Compose installation completed."

log "INFO" "Fetching the latest BlockMesh CLI release..."
LATEST_VERSION=$(curl -s $BLOCKMESH_API_URL | grep -Po '"tag_name": "\K.*?(?=")')
DOWNLOAD_URL="https://github.com/block-mesh/block-mesh-monorepo/releases/download/${LATEST_VERSION}/blockmesh-cli-x86_64-unknown-linux-gnu.tar.gz"

log "INFO" "Downloading BlockMesh CLI from: ${DOWNLOAD_URL}..."
curl -L "$DOWNLOAD_URL" -o blockmesh-cli.tar.gz

if file blockmesh-cli.tar.gz | grep -q 'gzip compressed data'; then
    mkdir -p target/release
    tar -xzf blockmesh-cli.tar.gz -C target/release
    CLI_PATH=$(find target/release -name 'blockmesh-cli' -type f | head -n 1)
    
    if [[ -f "$CLI_PATH" ]]; then
        chmod +x "$CLI_PATH"
        log "SUCCESS" "BlockMesh CLI downloaded and extracted successfully."
    else
        log "ERROR" "blockmesh-cli executable not found after extraction."
        exit 1
    fi
else
    log "ERROR" "Downloaded file is not a valid gzip format."
    exit 1
fi

# Ensure to prompt for email and password
read -p "Enter Email: " email
read -sp "Enter Password: " password
echo

# Check if the container already exists and remove it
if docker ps -a | grep -q "blockmesh-cli-container"; then
    log "INFO" "Stopping and removing existing BlockMesh CLI container..."
    docker stop blockmesh-cli-container || true
    docker rm blockmesh-cli-container || true
    log "SUCCESS" "Old container stopped and removed."
else
    log "INFO" "No existing BlockMesh CLI container found."
fi

log "INFO" "Creating a Docker container for the BlockMesh CLI..."
docker run -d \
    --name blockmesh-cli-container \
    --restart unless-stopped \
    -v "$(pwd)/$CLI_PATH:/app/blockmesh-cli" \
    -e EMAIL="$email" \
    -e PASSWORD="$password" \
    --workdir /app \
    ubuntu:22.04 "./blockmesh-cli" --email "$email" --password "$password"

log "INFO" "Checking the status of the BlockMesh CLI container..."
docker ps -a | grep blockmesh-cli-container

log "INFO" "Fetching logs for the BlockMesh CLI container (press Ctrl+C to stop)..."
docker logs -f blockmesh-cli-container

log "SUCCESS" "Setup completed successfully."
