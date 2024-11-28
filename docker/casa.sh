#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Setup logging
LOG_FILE="/userdata/system/casaos_install.log"
exec 1> >(tee -a "$LOG_FILE") 2>&1

# Function for cleanup on failure
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Installation failed with error code $exit_code. Check $LOG_FILE for details."
        # Cleanup temporary files
        rm -f "${HOME_DIR}"/batocera-casaos.tar.zip*
        rm -f "${HOME_DIR}"/batocera-casaos.tar.gz
        rm -f "${HOME_DIR}"/aria2c
    fi
    exit $exit_code
}

trap cleanup EXIT

# Function to check available disk space
check_disk_space() {
    local required_space=2000000  # Required space in KB (approximately 2GB)
    local available_space=$(df -k "${HOME_DIR}" | awk 'NR==2 {print $4}')
    
    if [ "$available_space" -lt "$required_space" ]; then
        echo "Error: Not enough disk space. Required: 2GB, Available: $(($available_space/1024))MB"
        exit 1
    fi
}

# Function to verify downloads
verify_download() {
    local file=$1
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "Error: Download failed or file is empty: $file"
        exit 1
    fi
}

echo "Batocera.PRO CasaOS installer..."
echo "Installation started at $(date)"
echo "This can take a while... please wait....."

# Define the home directory
HOME_DIR=/userdata/system

# Check if CasaOS is already installed
if [ -d "${HOME_DIR}/casaos" ]; then
    echo "CasaOS appears to be already installed."
    read -p "Do you want to remove the existing installation and continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
    rm -rf "${HOME_DIR}/casaos"
fi

# Check disk space
check_disk_space

# Define URLs with version control
CASA_VERSION="latest"
BASE_URL="https://github.com/LionCave97/batocera.pro/releases/download/batocera-containers"
ZIP_PARTS=(
    "${BASE_URL}/batocera-casaos.tar.zip.001"
    "${BASE_URL}/batocera-casaos.tar.zip.002"
    "${BASE_URL}/batocera-casaos.tar.zip.003"
    "${BASE_URL}/batocera-casaos.tar.zip.004"
)

# Download and verify each part
for part in "${ZIP_PARTS[@]}"; do
    filename=$(basename "$part")
    echo "Downloading $filename..."
    ./aria2c -x 10 --retry-wait=10 --max-tries=5 "$part" -o "$filename"
    verify_download "$filename"
done

# Combine the zip files
echo "Combining split zip files..."
cat batocera-casaos.tar.zip.* > batocera-casaos.tar.zip
if [ $? -ne 0 ]; then
    echo "Failed to combine the split zip files. Exiting."
    exit 1
fi

# Unzip the combined zip file
echo "Unzipping combined zip file..."
unzip -q "batocera-casaos.tar.zip"
if [ $? -ne 0 ]; then
    echo "Failed to unzip the file. Exiting."
    exit 1
fi

# Extract the tar.gz file
echo "Extracting the tar.gz file..."
tar -xzvf "batocera-casaos.tar.gz"
if [ $? -ne 0 ]; then
    echo "Failed to extract the tar.gz file. Exiting."
    exit 1
fi

# Clean up zip and tar files
rm batocera-casaos.tar.zip*
rm batocera-casaos.tar.gz

# Download the executable using aria2c
echo "Downloading the executable file..."
./aria2c -x 5 "https://github.com/LionCave97/batocera.pro/releases/download/batocera-containers/batocera-casaos" -o "casaos/batocera-casaos"

if [ $? -ne 0 ]; then
    echo "Failed to download executable. Exiting."
    exit 1
fi

# Make the executable runnable
chmod +x "/userdata/system/casaos/batocera-casaos"
if [ $? -ne 0 ]; then
    echo "Failed to make the file executable. Exiting."
    exit 1
fi

# Backup existing custom.sh
if [ -f ~/custom.sh ]; then
    cp ~/custom.sh ~/custom.sh.backup
fi

# Add casa to custom.sh for autostart (prevent duplicate entries)
if ! grep -q "casaos/batocera-casaos" ~/custom.sh 2>/dev/null; then
    echo "/userdata/system/casaos/batocera-casaos &" >> ~/custom.sh
fi

# Verify installation
if [ ! -x "${HOME_DIR}/casaos/batocera-casaos" ]; then
    echo "Error: Installation verification failed. Executable not found or not executable."
    exit 1
fi

# Run the executable in background
echo "Running CasaOS in background..."
"${HOME_DIR}/casaos/batocera-casaos" &

# Wait for service to start
echo "Waiting for CasaOS to start..."
for i in {1..30}; do
    if curl -s http://localhost:80 >/dev/null; then
        echo "CasaOS is running!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Warning: CasaOS may not have started properly. Please check manually."
    fi
    sleep 1
done

# Cleanup
rm -f aria2c

# Final status message
echo "Installation completed at $(date)"
echo "Log file available at: $LOG_FILE"

# Final dialog message with casaos management info
MSG="Casaos container has been set up.\n\nAccess casa Web UI at http://<your-batocera-ip>:80 \n\nRDP Debian XFCE Desktop port 3389 username/password is root/linux\n\nCasaos data stored in: ~/casaos\n\nDefault web ui username/password is batocera/batoceralinux"
dialog --title "Casaos Setup Complete" --msgbox "$MSG" 20 70

echo "Process completed successfully."

echo "1) to stop the container, run:  podman stop casaos"
echo "2) to enter zsh session, run:  podman exec -it casaos zsh"
