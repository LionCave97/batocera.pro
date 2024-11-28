#!/bin/bash

# Set strict error handling
set -euo pipefail
trap 'handle_error $? $LINENO' ERR

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Constants
HOME_DIR=/userdata/system
CASA_DIR="${HOME_DIR}/casaos"
REQUIRED_SPACE_MB=2048 # 2GB minimum
DOWNLOAD_TIMEOUT=300 # 5 minutes timeout for downloads

# Error handler function
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo -e "${RED}Error occurred in script at line ${line_number}${NC}"
    echo -e "${RED}Exit code: ${exit_code}${NC}"
    cleanup
    exit 1
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Performing cleanup...${NC}"
    rm -f "${HOME_DIR}"/batocera-casaos.tar.zip*
    rm -f "${HOME_DIR}"/batocera-casaos.tar.gz
    rm -f "${HOME_DIR}"/aria2c
}

# Check system requirements
check_system_requirements() {
    echo -e "${YELLOW}Checking system requirements...${NC}"
    
    # Check architecture
    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo -e "${RED}Error: This script requires x86_64 architecture${NC}"
        exit 1
    fi

    # Check available disk space
    local available_space=$(df -m "${HOME_DIR}" | awk 'NR==2 {print $4}')
    if [[ ${available_space} -lt ${REQUIRED_SPACE_MB} ]]; then
        echo -e "${RED}Error: Insufficient disk space. Required: ${REQUIRED_SPACE_MB}MB, Available: ${available_space}MB${NC}"
        exit 1
    fi

    # Check for required commands
    local required_commands=("curl" "unzip" "tar" "dialog")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}Error: Required command '$cmd' not found${NC}"
            exit 1
        fi
    done
}

# Download function with optimized aria2c settings
download_with_retry() {
    local url=$1
    local output=$2
    local max_retries=3
    local retry=0

    while [[ ${retry} -lt ${max_retries} ]]; do
        if timeout ${DOWNLOAD_TIMEOUT} ./aria2c \
            -x 16 \                          # Increase max connections per server
            -s 16 \                          # Increase concurrent downloads
            -k 1M \                          # Piece selection size
            --min-split-size=1M \            # Min split size
            --max-connection-per-server=16 \ # Max connections per server
            --optimize-concurrent-downloads \
            --file-allocation=none \         # Disable file pre-allocation
            --retry-wait=3 \                 # Reduce retry wait time
            --auto-file-renaming=false \
            --allow-overwrite=true \
            "${url}" -o "${output}"; then
            return 0
        fi
        retry=$((retry + 1))
        echo -e "${YELLOW}Retry ${retry}/${max_retries} for ${output}${NC}"
        sleep 2
    done
    
    echo -e "${RED}Failed to download ${output} after ${max_retries} attempts${NC}"
    return 1
}

# Main installation function
install_casaos() {
    echo -e "${GREEN}Starting CasaOS installation...${NC}"
    
    # Create necessary directories
    mkdir -p "${CASA_DIR}"
    
    # Download and setup aria2c
    echo -e "${YELLOW}Setting up aria2c...${NC}"
    curl -L https://raw.githubusercontent.com/LionCave97/batocera.pro/main/.dep/.scripts/aria2c.sh | bash
    
    # Define and download split files
    local base_url="https://github.com/LionCave97/batocera.pro/releases/download/batocera-containers"
    local files=("batocera-casaos.tar.zip.001" "batocera-casaos.tar.zip.002" 
                "batocera-casaos.tar.zip.003" "batocera-casaos.tar.zip.004")
    
    for file in "${files[@]}"; do
        echo -e "${YELLOW}Downloading ${file}...${NC}"
        download_with_retry "${base_url}/${file}" "${file}" || exit 1
    done

    # Combine and extract files
    echo -e "${YELLOW}Processing downloaded files...${NC}"
    cat batocera-casaos.tar.zip.* > batocera-casaos.tar.zip
    unzip -q batocera-casaos.tar.zip || { echo -e "${RED}Failed to unzip file${NC}"; exit 1; }
    tar -xzf batocera-casaos.tar.gz || { echo -e "${RED}Failed to extract tar file${NC}"; exit 1; }

    # Download and setup executable
    echo -e "${YELLOW}Setting up CasaOS executable...${NC}"
    download_with_retry "${base_url}/batocera-casaos" "casaos/batocera-casaos"
    chmod +x "${CASA_DIR}/batocera-casaos"

    # Configure autostart
    echo -e "${YELLOW}Configuring autostart...${NC}"
    if ! grep -q "casaos/batocera-casaos" "${HOME_DIR}/custom.sh" 2>/dev/null; then
        echo "${CASA_DIR}/batocera-casaos &" >> "${HOME_DIR}/custom.sh"
    fi

    # Start CasaOS
    echo -e "${GREEN}Starting CasaOS...${NC}"
    "${CASA_DIR}/batocera-casaos" &

    # Display completion message
    local msg="CasaOS container has been set up.\n\n"
    msg+="Access casa Web UI at http://<your-batocera-ip>:80\n\n"
    msg+="RDP Debian XFCE Desktop port 3389\n"
    msg+="Username: root\n"
    msg+="Password: linux\n\n"
    msg+="CasaOS data stored in: ${CASA_DIR}\n\n"
    msg+="Default web UI credentials:\n"
    msg+="Username: batocera\n"
    msg+="Password: batoceralinux"
    
    dialog --title "CasaOS Setup Complete" --msgbox "${msg}" 22 70

    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "${YELLOW}Management commands:${NC}"
    echo "1) To stop the container: podman stop casaos"
    echo "2) To enter zsh session: podman exec -it casaos zsh"
}

# Main execution
main() {
    check_system_requirements
    install_casaos
    cleanup
}

main
