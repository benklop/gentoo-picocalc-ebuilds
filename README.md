# Gentoo Overlay Management Scripts

This repository contains scripts for managing the `picocalc-ebuilds` Gentoo overlay using Docker containers.

## Prerequisites

- Docker installed and running
- Sufficient disk space for Gentoo Docker images and build processes
- Internet connection for downloading Docker images and syncing Portage tree

## Quick Start

1. **Build the intermediate image (one-time setup):**
   ```bash
   ./build-intermediate-image.sh
   ```

2. **Update package manifests:**
   ```bash
   ./update-manifest.sh sys-apps/openrc
   ```

## Scripts

### 1. `build-intermediate-image.sh`

Creates an intermediate Docker image with Portage already synced for faster manifest generation.

**Usage:**
```bash
./build-intermediate-image.sh
```

**What it does:**
- Pulls the latest Gentoo stage3 Docker image
- Syncs the complete Portage tree
- Installs commonly needed tools
- Saves the result as `gentoo-picocalc-overlay:latest`

**When to run:**
- Initial setup (required before using other scripts)
- Weekly to keep Portage tree updated
- After major Gentoo updates

### 2. `update-manifest.sh`

Updates the Manifest file for a specific package.

**Usage:**
```bash
./update-manifest.sh [--no-sync] <category/package>
```

**Arguments:**
- `category/package`: The package in format `category/package` (e.g., `sys-apps/openrc`, `sys-devel/android-adbd`)

**Options:**
- `--no-sync`: Skip Portage tree sync (faster but may fail for complex packages)

**Examples:**
```bash
./update-manifest.sh sys-apps/openrc
./update-manifest.sh --no-sync sys-apps/openrc
./update-manifest.sh sys-devel/android-adbd
```

**What it does:**
- Validates that the specified package exists
- Uses pre-built intermediate image (if available) or pulls base Gentoo image
- Starts a container with the overlay mounted
- Uses pre-synced Portage tree or syncs if using base image
- Configures the overlay in the container
- Removes the existing Manifest file
- Generates a new Manifest using `ebuild <package>.ebuild manifest`
- Shows a summary of the generated Manifest contents

**Performance:**
- **With intermediate image:** ~30-60 seconds
- **Without intermediate image:** ~5-10 minutes (includes Portage sync)

**When to use --no-sync:**
- Quick iterations when using the intermediate image
- Simple packages that you know work without dependency resolution

## Usage Examples

```bash
# One-time setup: build intermediate image
./build-intermediate-image.sh

# Update manifest for specific packages (fast with intermediate image)
./update-manifest.sh sys-apps/openrc
./update-manifest.sh sys-devel/android-adbd

# Update manifest without sync (even faster)
./update-manifest.sh --no-sync sys-apps/openrc

# See help and available packages
./update-manifest.sh
```

## Maintenance

### Updating the Intermediate Image

The intermediate image should be rebuilt periodically to keep the Portage tree current:

```bash
# Rebuild weekly or after major Gentoo updates
./build-intermediate-image.sh
```

### Cleaning Up

To remove the intermediate image and save disk space:

```bash
docker rmi gentoo-picocalc-overlay:latest
```

To remove all related containers and images:

```bash
docker system prune -f
docker rmi gentoo-picocalc-overlay:latest gentoo/stage3:latest
```

## Available Packages

Run `./update-manifest.sh` without arguments to see a list of available packages in the overlay.

Current packages:
- `sys-apps/openrc`
- `sys-devel/android-adbd`

## Troubleshooting

### Docker Issues
- Ensure Docker is installed: `docker --version`
- Ensure Docker daemon is running: `docker info`
- Check Docker permissions: You may need to add your user to the `docker` group

### Permission Issues
- The scripts automatically handle file ownership within the containers
- Generated files should have the correct ownership matching the host user

### Network Issues
- Ensure internet connectivity for downloading Docker images
- The Gentoo container needs to sync the Portage tree, which requires internet access

## Technical Details

Both scripts:
- Use the `gentoo/stage3:latest` Docker image as the base
- Mount the overlay directory into the container at `/var/db/repos/picocalc-ebuilds`
- Sync the Portage tree for access to base system functionality
- Configure the overlay properly within the container's Portage environment
- Clean up containers automatically on exit (including interruption)
- Provide colored output for better user experience
- Include comprehensive error checking and validation

The containers are ephemeral and are automatically removed after the scripts complete or are interrupted.