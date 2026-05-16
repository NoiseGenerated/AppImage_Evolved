#!/bin/bash
# ==============================================================================
# --- "THE EVOLVED STAGING SCRIPT (AUTOMATED DOWNSTREAM)" ---
# Project: AppImage_Evolved
# Author: NoiseGenerated
# GitHub: https://github.com/NoiseGenerated/AppImage_Evolved
#
# Description:
#   Stages the read-only infrastructure server environment and autonomously 
#   fetches the latest official WordPress zip package via wget to place it 
#   in the launch directory.
# ==============================================================================
set -e

WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$WORKING_DIR/binaries"
TARGET_DIR="$WORKING_DIR/squashfs-root"

cd "$WORKING_DIR"

echo "--- [ STARTING AUTOMATED INFRASTRUCTURE STAGING ] ---"

# 1. Fetch the absolute latest WordPress upstream archive
echo "Checking for upstream web application package..."
if [ ! -f "wordpress-latest.zip" ]; then
    echo "Downloading latest official WordPress core release..."
    wget -q --show-progress "https://wordpress.org/latest.zip" -O "wordpress-latest.zip"
    echo "[+] Download Complete: wordpress-latest.zip"
else
    echo "[+] Upstream package 'wordpress-latest.zip' already exists locally. Skipping download."
fi

# 2. Reset and clear old filesystem structures
echo "Cleaning up any old staging directories..."
rm -rf "$TARGET_DIR"

# 3. Create core server layout
echo "Constructing skeleton directories..."
mkdir -p "$TARGET_DIR/etc"
mkdir -p "$TARGET_DIR/usr/bin"
mkdir -p "$TARGET_DIR/usr/lib"

# 4. Deploy LinuxBrew Binaries into read-only layout
echo "Staging binaries into read-only layer..."
REQUIRED_BINS=("mariadb-admin" "mariadbd" "mariadb-install-db" "nginx" "php" "php-fpm")

for binary in "${REQUIRED_BINS[@]}"; do
    if [ -f "$BIN_DIR/$binary" ]; then
        cp "$BIN_DIR/$binary" "$TARGET_DIR/usr/bin/"
        chmod +x "$TARGET_DIR/usr/bin/$binary"
    else
        echo "CRITICAL ERROR: Missing required binary: $BIN_DIR/$binary"
        exit 1
    fi
done

# 5. Stash host system Dynamic Linker dependency
echo "Staging system dynamic linker..."
if [ -d "/usr/lib64" ]; then 
    LIB_SOURCE="/usr/lib64" 
else 
    LIB_SOURCE="/usr/lib" 
fi
cp "$LIB_SOURCE/ld-linux-x86-64.so.2" "$TARGET_DIR/usr/lib/" 2>/dev/null || true

echo "------------------------------------------------"
echo "INFRASTRUCTURE STAGED & APPLICATION FETCHED!"
echo "You can now safely execute: ./evolved_builder.sh"
echo "------------------------------------------------"
