#!/bin/bash
# Update package manifest for a specific package using Gentoo Docker container

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="${SCRIPT_DIR}"

# Usage function
usage() {
    echo "Usage: $0 [--no-sync] <category/package>"
    echo ""
    echo "Update the Manifest file for a specific package in the overlay"
    echo ""
    echo "Arguments:"
    echo "  category/package    The package in format category/package (e.g., sys-apps/openrc)"
    echo ""
    echo "Options:"
    echo "  --no-sync           Skip Portage tree sync (faster but may fail for complex packages)"
    echo ""
    echo "Examples:"
    echo "  $0 sys-apps/openrc"
    echo "  $0 --no-sync sys-apps/openrc"
    echo "  $0 sys-devel/android-adbd"
    echo ""
    echo "Available packages:"
    find "${OVERLAY_DIR}" -mindepth 2 -maxdepth 2 -type d -path "*/.*" -prune -o -type d -print | sed "s|${OVERLAY_DIR}/||" | grep -E '^[^./][^/]*/[^./][^/]*$' | sort
    exit 1
}

# Parse arguments
SYNC_PORTAGE=true
PACKAGE_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-sync)
            SYNC_PORTAGE=false
            shift
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            echo ""
            usage
            ;;
        *)
            if [[ -n "${PACKAGE_ARG}" ]]; then
                echo -e "${RED}Error: Too many arguments${NC}"
                echo ""
                usage
            fi
            PACKAGE_ARG="$1"
            shift
            ;;
    esac
done

if [[ -z "${PACKAGE_ARG}" ]]; then
    echo -e "${RED}Error: No package specified${NC}"
    echo ""
    usage
fi

# Validate format and extract category/package
if [[ ! "${PACKAGE_ARG}" =~ ^[^/]+/[^/]+$ ]]; then
    echo -e "${RED}Error: Invalid package format. Expected 'category/package' (e.g., 'sys-apps/openrc')${NC}"
    echo ""
    usage
fi

CATEGORY="${PACKAGE_ARG%%/*}"
PACKAGE="${PACKAGE_ARG##*/}"
PACKAGE_DIR="${OVERLAY_DIR}/${CATEGORY}/${PACKAGE}"

# Validate package directory exists
if [[ ! -d "${PACKAGE_DIR}" ]]; then
    echo -e "${RED}Error: Package directory does not exist: ${PACKAGE_DIR}${NC}"
    echo ""
    usage
fi

echo -e "${GREEN}Updating manifest for ${BLUE}${CATEGORY}/${PACKAGE}${GREEN}...${NC}"

# Function to cleanup on exit
cleanup() {
    if [[ -n "${CONTAINER_ID:-}" ]]; then
        echo -e "${YELLOW}Cleaning up container...${NC}"
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

echo -e "${YELLOW}Pulling latest Gentoo Docker image...${NC}"
# Try to use intermediate image first, fall back to base image
if docker image inspect "${INTERMEDIATE_IMAGE}" >/dev/null 2>&1; then
    DOCKER_IMAGE="${INTERMEDIATE_IMAGE}"
    echo -e "${GREEN}Using intermediate image with pre-synced Portage tree${NC}"
else
    DOCKER_IMAGE="${BASE_IMAGE}"
    echo -e "${BLUE}Intermediate image not found, using base image${NC}"
    echo -e "${BLUE}Run './build-intermediate-image.sh' to create faster intermediate image${NC}"
    docker pull "${DOCKER_IMAGE}"
fi

echo -e "${YELLOW}Starting Gentoo container...${NC}"
CONTAINER_ID=$(docker run -d \
    --name "gentoo-manifest-update-$$" \
    -v "${OVERLAY_DIR}:/var/db/repos/${OVERLAY_NAME}:rw" \
    "${DOCKER_IMAGE}" \
    sleep 3600)

if [[ "${SYNC_PORTAGE}" == "true" ]]; then
    if [[ "${DOCKER_IMAGE}" == "${INTERMEDIATE_IMAGE}" ]]; then
        echo -e "${GREEN}Using pre-synced Portage tree from intermediate image${NC}"
    else
        echo -e "${YELLOW}Syncing Portage tree in container (this may take a few minutes)...${NC}"
        docker exec "${CONTAINER_ID}" emerge --sync
    fi
else
    echo -e "${BLUE}Skipping Portage sync (use without --no-sync flag if manifest generation fails)${NC}"
fi

echo -e "${YELLOW}Configuring overlay in container...${NC}"
docker exec "${CONTAINER_ID}" bash -c "
    # Add overlay to repos.conf
    mkdir -p /etc/portage/repos.conf
    cat > /etc/portage/repos.conf/${OVERLAY_NAME}.conf << 'EOF'
[${OVERLAY_NAME}]
location = /var/db/repos/${OVERLAY_NAME}
masters = gentoo
auto-sync = no
EOF
"

echo -e "${YELLOW}Removing existing Manifest file...${NC}"
if [[ -f "${PACKAGE_DIR}/Manifest" ]]; then
    rm -f "${PACKAGE_DIR}/Manifest"
    echo -e "${BLUE}Removed existing Manifest for ${CATEGORY}/${PACKAGE}${NC}"
fi

echo -e "${YELLOW}Generating new Manifest file...${NC}"
docker exec "${CONTAINER_ID}" bash -c "
    cd /var/db/repos/${OVERLAY_NAME}/${CATEGORY}/${PACKAGE}
    
    # Generate new manifest using ebuild command
    for ebuild_file in *.ebuild; do
        if [[ -f \"\$ebuild_file\" ]]; then
            echo \"Processing \$ebuild_file...\"
            if ! ebuild \"\$ebuild_file\" manifest; then
                echo \"Error: Failed to generate manifest for \$ebuild_file\"
                echo \"This might be due to missing dependencies in Portage tree.\"
                echo \"Try running without --no-sync flag for a complete Portage tree.\"
                exit 1
            fi
            break
        fi
    done
    
    # Set proper permissions
    chown \$(stat -c '%u:%g' .) Manifest
    
    echo 'Manifest generation completed for ${CATEGORY}/${PACKAGE}'
"

# Verify the manifest was created
if [[ -f "${PACKAGE_DIR}/Manifest" ]]; then
    echo -e "${GREEN}✓ Manifest successfully updated for ${BLUE}${CATEGORY}/${PACKAGE}${NC}"
    echo -e "${GREEN}New Manifest location: ${PACKAGE_DIR}/Manifest${NC}"
    
    # Show a summary of the manifest contents
    echo -e "${YELLOW}Manifest contents:${NC}"
    cat "${PACKAGE_DIR}/Manifest" | head -10
    if [[ $(wc -l < "${PACKAGE_DIR}/Manifest") -gt 10 ]]; then
        echo "... (showing first 10 lines only)"
    fi
else
    echo -e "${RED}Error: Manifest file was not created${NC}"
    exit 1
fi

# Container will be cleaned up by trap