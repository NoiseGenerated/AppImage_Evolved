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
#   in the launch directory. Includes MariaDB share files required for init.
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
mkdir -p "$TARGET_DIR/usr/share/mysql"

# 4. Deploy LinuxBrew Binaries into read-only layout
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

# 4.5 Stash MariaDB Support Files (Required for mariadb-install-db)
echo "Staging MariaDB share templates..."
SHARE_FOUND=false

# Dynamically hunt for the templates, including deep within versioned Homebrew Cellars
SEARCH_PATHS=(
    $(ls -d /home/linuxbrew/.linuxbrew/Cellar/mariadb/*/share/mariadb 2>/dev/null || true)
    $(ls -d /home/linuxbrew/.linuxbrew/Cellar/mariadb/*/share/mysql 2>/dev/null || true)
    $(ls -d /var/home/linuxbrew/.linuxbrew/Cellar/mariadb/*/share/mariadb 2>/dev/null || true)
    $(ls -d /var/home/linuxbrew/.linuxbrew/Cellar/mariadb/*/share/mysql 2>/dev/null || true)
    "/home/linuxbrew/.linuxbrew/share/mariadb"
    "/home/linuxbrew/.linuxbrew/share/mysql"
    "/usr/share/mariadb"
    "/usr/share/mysql"
)

for path in "${SEARCH_PATHS[@]}"; do
    # Only copy if the directory exists AND the specific missing SQL file is actually inside it
    if [ -d "$path" ] && [ -f "$path/fill_help_tables.sql" ]; then
        cp -r "$path"/* "$TARGET_DIR/usr/share/mysql/"
        SHARE_FOUND=true
        echo "[+] Found and copied SQL templates from: $path"
        break
    fi
done

if [ "$SHARE_FOUND" = false ]; then
    echo "WARNING: Could not automatically locate the host's MariaDB 'share' directory containing fill_help_tables.sql."
    echo "If database initialization fails, you may need to manually copy those files into $TARGET_DIR/usr/share/mysql"
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
