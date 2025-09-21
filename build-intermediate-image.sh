#!/bin/bash
# Build or update the intermediate Gentoo container image with Portage synced

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_IMAGE="gentoo/stage3:latest"
INTERMEDIATE_IMAGE="gentoo-picocalc-overlay:latest"
OVERLAY_NAME="picocalc-ebuilds"

echo -e "${GREEN}Building intermediate Gentoo container image with synced Portage...${NC}"

# Function to cleanup on exit
cleanup() {
    if [[ -n "${CONTAINER_ID:-}" ]]; then
        echo -e "${YELLOW}Cleaning up build container...${NC}"
        docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    exit 1
fi

echo -e "${YELLOW}Pulling latest base Gentoo Docker image...${NC}"
docker pull "${BASE_IMAGE}"

echo -e "${YELLOW}Starting build container...${NC}"
CONTAINER_ID=$(docker run -d \
    --name "gentoo-overlay-build-$$" \
    "${BASE_IMAGE}" \
    sleep 3600)

echo -e "${YELLOW}Syncing Portage tree in container (this will take several minutes)...${NC}"
docker exec "${CONTAINER_ID}" emerge --sync

echo -e "${YELLOW}Configuring overlay support...${NC}"
docker exec "${CONTAINER_ID}" bash -c "
    # Create repos.conf directory
    mkdir -p /etc/portage/repos.conf
    
    # Install any commonly needed tools
    emerge -q --oneshot app-portage/gentoolkit
"

echo -e "${YELLOW}Committing intermediate image...${NC}"
docker commit "${CONTAINER_ID}" "${INTERMEDIATE_IMAGE}"

# Get image size for info
IMAGE_SIZE=$(docker images "${INTERMEDIATE_IMAGE}" --format "table {{.Size}}" | tail -1)

echo -e "${GREEN}✓ Intermediate image '${INTERMEDIATE_IMAGE}' created successfully!${NC}"
echo -e "${GREEN}Image size: ${IMAGE_SIZE}${NC}"
echo -e "${BLUE}This image contains a synced Portage tree and will speed up manifest generation.${NC}"
echo ""
echo -e "${YELLOW}To rebuild this image periodically (recommended weekly):${NC}"
echo -e "  $0"
echo ""
echo -e "${YELLOW}To remove the intermediate image if no longer needed:${NC}"
echo -e "  docker rmi ${INTERMEDIATE_IMAGE}"

# Container will be cleaned up by trap