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
GITHUB_BASE_URL="https://github.com/LionCave97/batocera.pro/releases/download/batocera-containers"

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

# Function to check and setup aria2c
setup_aria2c() {
    local aria2c_path=""
    
    # First check if aria2c exists in PATH
    if command -v aria2c >/dev/null 2>&1; then
        echo -e "${GREEN}Found system aria2c installation${NC}"
        aria2c_path="aria2c"
    # Then check if it exists in common Batocera locations
    elif [ -f "/userdata/system/pro/.dep/aria2c" ]; then
        echo -e "${GREEN}Found existing aria2c in pro/.dep${NC}"
        aria2c_path="/userdata/system/pro/.dep/aria2c"
        chmod +x "$aria2c_path"
    else
        echo -e "${YELLOW}Downloading aria2c...${NC}"
        # Create .dep directory if it doesn't exist
        mkdir -p "/userdata/system/pro/.dep"
        
        # Download aria2c
        if curl -L "https://github.com/uureel/batocera.pro/raw/main/.dep/aria2c" -o "/userdata/system/pro/.dep/aria2c"; then
            chmod +x "/userdata/system/pro/.dep/aria2c"
            aria2c_path="/userdata/system/pro/.dep/aria2c"
            echo -e "${GREEN}Successfully installed aria2c${NC}"
        else
            echo -e "${RED}Failed to download aria2c${NC}"
            exit 1
        fi
    fi
    
    # Export the aria2c path for use in other functions
    export ARIA2C_PATH="$aria2c_path"
}

# Download function with resume capability and better error handling
download_with_retry() {
    local url=$1
    local output=$2
    local max_retries=3
    local retry=0
    local continue_file="${output}.aria2"  # aria2 control file
    
    while [[ ${retry} -lt ${max_retries} ]]; do
        echo -e "${YELLOW}Download attempt $((retry + 1)) for ${output}${NC}"
        
        # Get fresh download URL (GitHub releases expire)
        local fresh_url=$(curl -sI "$url" | grep -i "location:" | cut -d' ' -f2 | tr -d '\r\n')
        if [[ -z "$fresh_url" ]]; then
            fresh_url="$url"  # Fallback to original URL if redirect not found
        fi

        # Check if partial download exists and is valid
        if [[ -f "$continue_file" ]]; then
            echo -e "${YELLOW}Resuming previous download...${NC}"
        fi

        if timeout ${DOWNLOAD_TIMEOUT} "${ARIA2C_PATH}" \
            -x16 -s16 -k1M \
            --min-split-size=1M \
            --max-connection-per-server=16 \
            --optimize-concurrent-downloads=true \
            --file-allocation=none \
            --retry-wait=3 \
            --auto-file-renaming=false \
            --allow-overwrite=true \
            --continue=true \
            --max-tries=0 \
            --connect-timeout=10 \
            --timeout=10 \
            "${fresh_url}" \
            -o "${output}"; then
            
            # Verify download completed successfully
            if [[ -f "${output}" ]]; then
                echo -e "${GREEN}Successfully downloaded ${output}${NC}"
                return 0
            fi
        fi

        retry=$((retry + 1))
        if [[ ${retry} -lt ${max_retries} ]]; then
            echo -e "${YELLOW}Download failed, waiting 5 seconds before retry ${retry}/${max_retries}${NC}"
            sleep 5
        fi
    done
    
    echo -e "${RED}Failed to download ${output} after ${max_retries} attempts${NC}"
    return 1
}

# Add this function to check if files are already downloaded and extracted
check_existing_files() {
    local file=$1
    local size_threshold=1000000  # 1MB minimum size

    if [[ -f "$file" ]]; then
        local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        if [[ $file_size -gt $size_threshold ]]; then
            return 0  # File exists and is large enough
        fi
    fi
    return 1  # File doesn't exist or is too small
}

# Update the download_split_files function
download_split_files() {
    local files=(
        "batocera-casaos.tar.zip.001"
        "batocera-casaos.tar.zip.002"
        "batocera-casaos.tar.zip.003"
        "batocera-casaos.tar.zip.004"
    )

    for file in "${files[@]}"; do
        if check_existing_files "${file}"; then
            echo -e "${GREEN}${file} already exists, skipping download...${NC}"
            continue
        fi
        echo -e "${YELLOW}Downloading ${file}...${NC}"
        if ! download_with_retry "${GITHUB_BASE_URL}/${file}" "${file}"; then
            echo -e "${RED}Failed to download ${file}. Aborting.${NC}"
            return 1
        fi
    done
    return 0
}

# Function to get user choice using dialog
get_user_choice() {
    local title=$1
    local text=$2
    local options=$3
    
    # Create temporary file for dialog output
    local temp_file=$(mktemp)
    
    # Display dialog and capture choice
    dialog --clear --title "$title" \
           --menu "$text" 15 60 3 \
           $options \
           2>"$temp_file"
    
    local status=$?
    local choice=$(cat "$temp_file")
    rm -f "$temp_file"
    
    # Check if user pressed cancel or escape
    if [ $status -ne 0 ]; then
        echo "3"  # Return exit option
        return
    fi
    
    echo "$choice"
}

# Update the check_installation_state function
check_installation_state() {
    local has_split_files=false
    local has_combined_zip=false
    local has_executable=false
    local installation_complete=false

    # Check split files
    if [[ -f "batocera-casaos.tar.zip.001" ]] && \
       [[ -f "batocera-casaos.tar.zip.002" ]] && \
       [[ -f "batocera-casaos.tar.zip.003" ]] && \
       [[ -f "batocera-casaos.tar.zip.004" ]]; then
        has_split_files=true
    fi

    # Check combined zip and executable
    [[ -f "batocera-casaos.tar.zip" ]] && has_combined_zip=true
    [[ -x "${CASA_DIR}/batocera-casaos" ]] && has_executable=true

    # If executable exists, consider it a complete installation
    $has_executable && installation_complete=true

    # If any files exist but installation isn't complete, it's partial
    if $has_split_files || $has_combined_zip || [[ -d "${CASA_DIR}" ]]; then
        if ! $installation_complete; then
            # Build status message
            local status_msg="Found:\n"
            $has_split_files && status_msg+="- Split archive files\n"
            $has_combined_zip && status_msg+="- Combined archive\n"
            [[ -d "${CASA_DIR}" ]] && status_msg+="- CasaOS directory\n"
            
            # Get user choice using dialog
            local choice=$(get_user_choice "Partial Installation Detected" \
                "$status_msg\nWhat would you like to do?" \
                "1 'Continue from where it left off' \
                 2 'Start fresh (delete and reinstall)' \
                 3 'Exit'")
            
            case $choice in
                1)
                    echo -e "${GREEN}Continuing existing installation...${NC}"
                    return 0
                    ;;
                2)
                    echo -e "${YELLOW}Cleaning up existing files...${NC}"
                    cleanup_installation
                    return 0
                    ;;
                3|"")
                    echo -e "${YELLOW}Exiting installation...${NC}"
                    exit 0
                    ;;
            esac
        else
            # Complete installation detected
            if dialog --title "Complete Installation Detected" \
                     --yesno "Would you like to reinstall?" 7 60; then
                echo -e "${YELLOW}Cleaning up existing installation...${NC}"
                cleanup_installation
                return 0
            else
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
            fi
        fi
    fi
}

# Function to cleanup existing installation
cleanup_installation() {
    echo -e "${YELLOW}Removing existing files...${NC}"
    rm -f batocera-casaos.tar.zip*
    rm -f batocera-casaos.tar.gz
    rm -rf "${CASA_DIR}"
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Main installation function
install_casaos() {
    echo -e "${GREEN}Starting CasaOS installation...${NC}"
    
    # Setup aria2c first
    setup_aria2c
    
    # Check installation state before proceeding
    check_installation_state
    
    # Create necessary directories
    mkdir -p "${CASA_DIR}"
    
    cd "${HOME_DIR}"

    # Check if CasaOS is already extracted
    if [[ -f "${CASA_DIR}/batocera-casaos" ]]; then
        echo -e "${GREEN}CasaOS files already extracted${NC}"
    else
        # Download split files if needed
        if ! download_split_files; then
            echo -e "${RED}Download failed. Exiting.${NC}"
            exit 1
        fi

        # Process the downloaded files
        echo -e "${YELLOW}Processing downloaded files...${NC}"
        if [[ ! -f "batocera-casaos.tar.zip" ]]; then
            echo -e "${YELLOW}Combining split files...${NC}"
            cat batocera-casaos.tar.zip.* > batocera-casaos.tar.zip
        fi
        
        if [[ ! -f "batocera-casaos.tar.gz" ]]; then
            echo -e "${YELLOW}Unzipping archive...${NC}"
            unzip -q "batocera-casaos.tar.zip" || { echo -e "${RED}Failed to unzip file${NC}"; exit 1; }
        fi
        
        echo -e "${YELLOW}Extracting CasaOS files...${NC}"
        # First check if the tar file contains what we expect
        tar -tvzf "batocera-casaos.tar.gz" || { echo -e "${RED}Invalid tar file${NC}"; exit 1; }
        
        # Create a temporary directory for extraction
        local temp_dir="${HOME_DIR}/casaos_temp"
        mkdir -p "${temp_dir}"
        
        # Extract to temporary directory first
        echo -e "${YELLOW}Extracting to temporary directory...${NC}"
        tar -xzf "batocera-casaos.tar.gz" -C "${temp_dir}" || { 
            echo -e "${RED}Failed to extract tar file${NC}"
            rm -rf "${temp_dir}"
            exit 1
        }
        
        # Move files to final location
        echo -e "${YELLOW}Moving files to final location...${NC}"
        if [[ -d "${temp_dir}/casaos" ]]; then
            # Move contents of nested casaos directory
            mv "${temp_dir}/casaos"/* "${CASA_DIR}/" || {
                echo -e "${RED}Failed to move files${NC}"
                rm -rf "${temp_dir}"
                exit 1
            }
            
            # Copy the executable files
            if [[ -f "${CASA_DIR}/filemanagerlauncher" ]]; then
                chmod +x "${CASA_DIR}/filemanagerlauncher"
                echo -e "${GREEN}Set permissions for filemanagerlauncher${NC}"
            fi
            
            if [[ -f "${CASA_DIR}/save.sh" ]]; then
                chmod +x "${CASA_DIR}/save.sh"
                echo -e "${GREEN}Set permissions for save.sh${NC}"
            fi
            
            echo -e "${GREEN}Successfully moved CasaOS files${NC}"
        else
            echo -e "${RED}Expected directory structure not found${NC}"
            echo -e "${YELLOW}Contents of temp directory:${NC}"
            ls -la "${temp_dir}"
            rm -rf "${temp_dir}"
            exit 1
        fi
        
        # Cleanup temporary directory
        rm -rf "${temp_dir}"
    fi

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
