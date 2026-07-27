#!/bin/bash
# ==============================================================================
# --- "THE EVOLVED STAGING SCRIPT (AUTOMATED DOWNSTREAM)" ---
# Project: AppImage_Evolved
# Author: NoiseGenerated
# GitHub: https://github.com/NoiseGenerated/AppImage_Evolved
#
# Description:
#   Stages the read-only infrastructure server environment from local binaries 
#   and autonomously fetches the latest official WordPress zip package.
# ==============================================================================
set -e

WORKING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$WORKING_DIR/binaries"
TARGET_DIR="$WORKING_DIR/squashfs-root"

cd "$WORKING_DIR"

echo "--- [ STARTING AUTOMATED INFRASTRUCTURE STAGING ] ---"

# 0. Auto-Extract Binaries if missing
if [ ! -d "$BIN_DIR" ]; then
    echo "Binaries directory missing. Searching for archives..."
    if [ -f "binaries.7z" ]; then
        if ! command -v 7z &> /dev/null; then 
            echo "CRITICAL ERROR: '7z' is required to unpack binaries.7z. Please install p7zip."
            exit 1
        fi
        echo "Extracting binaries.7z..."
        7z x binaries.7z -o./ -y > /dev/null
    elif [ -f "binaries.zip" ]; then
        if ! command -v unzip &> /dev/null; then 
            echo "CRITICAL ERROR: 'unzip' is required to unpack binaries.zip. Please install unzip."
            exit 1
        fi
        echo "Extracting binaries.zip..."
        unzip -q binaries.zip -d ./
    else
        echo "CRITICAL ERROR: Could not find 'binaries' folder, 'binaries.7z', or 'binaries.zip'."
        exit 1
    fi
fi

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
mkdir -p "$TARGET_DIR/usr/share/mysql"

# 4. Deploy Binaries from local ./binaries into read-only layout
echo "Staging binaries into read-only layer..."
REQUIRED_BINS=("mariadb-admin" "mariadbd" "mariadb-install-db" "my_print_defaults" "nginx" "php" "php-fpm")

for binary in "${REQUIRED_BINS[@]}"; do
    if [ -f "$BIN_DIR/$binary" ]; then
        cp "$BIN_DIR/$binary" "$TARGET_DIR/usr/bin/"
        chmod +x "$TARGET_DIR/usr/bin/$binary"
    else
        echo "CRITICAL ERROR: Missing required binary: $BIN_DIR/$binary"
        exit 1
    fi
done

# 4.5 Stash MariaDB Support Files strictly from local assets if provided, 
# or fall back gracefully without hardcoding host machine paths.
echo "Staging MariaDB share templates..."
if [ -d "$BIN_DIR/share/mysql" ]; then
    cp -r "$BIN_DIR/share/mysql/*" "$TARGET_DIR/usr/share/mysql/"
elif [ -d "$BIN_DIR/share/mariadb" ]; then
    cp -r "$BIN_DIR/share/mariadb/*" "$TARGET_DIR/usr/share/mysql/"
else
    # If your binaries package includes the share files internally, copy them here. 
    # Otherwise, it relies on what's packed in binaries.7z.
    echo "[+] Utilizing local binary asset structure."
fi

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
