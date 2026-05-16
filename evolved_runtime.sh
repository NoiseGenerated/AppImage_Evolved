#!/bin/bash
# ==============================================================================
# Project: AppImage_Evolved
# Author: NoiseGenerated
# Description: Fixed to serve WordPress out of the writeable external FUSE slots.
# ==============================================================================
SLOT_SIZE_MB=500
SLOT_SIZE_BYTES=$((SLOT_SIZE_MB * 1024 * 1024))
MARKER="THE_STORAGE_ZONE_STARTS_HERE"

# Capture the real-world folder where the AppImage execution was triggered
LAUNCH_DIR="$(pwd)"

# Find the start of Slot 0
START_OFFSET=$(python3 -c "
import os
def find_ext4_start():
    file_path = '$0'
    magic = b'\x53\xEF'
    block_size = 4096
    magic_offset_in_block = 1080
    with open(file_path, 'rb') as f:
        f.seek(0)
        content = f.read(20000)
        marker_pos = content.find(b'$MARKER')
        if marker_pos == -1: return
        start_search = ((marker_pos + len(b'$MARKER') + block_size - 1) // block_size) * block_size
        f.seek(start_search)
        while True:
            curr_pos = f.tell()
            f.seek(curr_pos + magic_offset_in_block)
            sig = f.read(2)
            if not sig: break
            if sig == magic:
                print(curr_pos)
                return
            f.seek(curr_pos + block_size)
find_ext4_start()
")

if [ -z "$START_OFFSET" ]; then
    echo "CRITICAL ERROR: Valid EXT4 Slot 0 not found."
    exit 1
fi

get_off() { echo $((START_OFFSET + ($1 * SLOT_SIZE_BYTES))); }

MOUNT_A="/tmp/vault_a_$$"
MOUNT_B="/tmp/vault_b_$$"
mkdir -p "$MOUNT_A" "$MOUNT_B"

emergency_cleanup() {
    echo -e "\n\n\e[31m[!] Emergency Intercept: Initiating Surgical Shutdown...\e[0m"
    if [ -n "$MARIADB_PID" ]; then kill "$MARIADB_PID" 2>/dev/null; fi
    if [ -n "$PHPFPM_PID" ]; then kill "$PHPFPM_PID" 2>/dev/null; fi
    if [ -n "$NGINX_PID" ]; then kill "$NGINX_PID" 2>/dev/null; fi
    sleep 1
    sync
    fusermount -u -z "$MOUNT_A" 2>/dev/null || true
    fusermount -u -z "$MOUNT_B" 2>/dev/null || true
    rm -rf "$MOUNT_A" "$MOUNT_B"
    echo -e "\e[32m[+] Stale Mounts Wiped. System Clean.\e[0m"
    exit 0
}
trap emergency_cleanup SIGINT SIGTERM

if [ -z "$APPDIR" ]; then
    APPDIR="$(cd "$(dirname "$0")" && pwd)/squashfs-root"
fi

export LD_LIBRARY_PATH="$APPDIR/usr/lib:$LD_LIBRARY_PATH"
export PATH="$APPDIR/usr/bin:$APPDIR/usr/sbin:$PATH"

echo "--- [ AppImage Evolved Vault Manager ] ---"
read -p "Selection ([Enter] Work / [V] Sync): " USER_CHOICE

if [[ "$USER_CHOICE" =~ ^[Vv]$ ]]; then
    read -p "Target Slot [3 or 4]: " VAULT_TARGET
    fuse2fs -o offset=$(get_off 0),ro "$0" "$MOUNT_A"
    fuse2fs -o offset=$(get_off $VAULT_TARGET),rw,uid=$(id -u),gid=$(id -g) "$0" "$MOUNT_B"
    rsync -a --delete --exclude 'lost+found' "$MOUNT_A/" "$MOUNT_B/"
    echo "Sync Complete."
else
    if fuse2fs -o offset=$(get_off 0),rw,noexec,nodev,uid=$(id -u),gid=$(id -g) "$0" "$MOUNT_A"; then
        sleep 1
        mkdir -p "$MOUNT_A/db" "$MOUNT_A/www" "$MOUNT_A/run"
        
        # 1. GENERATE NGINX/PHP ENGINE CONFS ON WRITEABLE SLOTS
        cat <<EOF > "$MOUNT_A/run/mime.types"
types {
    text/html html; text/css css; text/xml xml;
    image/gif gif; image/jpeg jpeg jpg; image/png png;
    application/javascript js; application/json json;
    image/x-icon ico; application/font-woff woff;
}
EOF

        cat <<EOF > "$MOUNT_A/run/fastcgi_params"
fastcgi_param  QUERY_STRING       \$query_string;
fastcgi_param  REQUEST_METHOD     \$request_method;
fastcgi_param  CONTENT_TYPE       \$content_type;
fastcgi_param  CONTENT_LENGTH     \$content_length;
fastcgi_param  SCRIPT_NAME        \$fastcgi_script_name;
fastcgi_param  REQUEST_URI        \$request_uri;
fastcgi_param  DOCUMENT_URI       \$document_uri;
fastcgi_param  DOCUMENT_ROOT      \$document_root;
fastcgi_param  SERVER_PROTOCOL    \$server_protocol;
fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/\$nginx_version;
fastcgi_param  REMOTE_ADDR        \$remote_addr;
fastcgi_param  REMOTE_PORT        \$remote_port;
fastcgi_param  SERVER_ADDR        \$server_addr;
fastcgi_param  SERVER_PORT        \$server_port;
fastcgi_param  SERVER_NAME        \$server_name;
fastcgi_param  HTTPS              \$https if_not_empty;
EOF

        cat <<EOF > "$MOUNT_A/run/nginx.conf"
worker_processes 1;
daemon off;
error_log "$MOUNT_A/run/nginx_error.log" warn;
pid "$MOUNT_A/run/nginx.pid";
events { worker_connections 1024; }
http {
    include "$MOUNT_A/run/mime.types";
    client_body_temp_path "$MOUNT_A/run/client_body";
    proxy_temp_path "$MOUNT_A/run/proxy_temp";
    fastcgi_temp_path "$MOUNT_A/run/fastcgi_temp";
    server {
        listen 8080;
        root "$MOUNT_A/www";
        index index.php index.html;
        location / { try_files \$uri \$uri/ /index.php?\$args; }
        location ~ \.php$ {
            fastcgi_pass unix:$MOUNT_A/run/php-fpm.sock;
            include "$MOUNT_A/run/fastcgi_params";
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        }
    }
}
EOF

        cat <<EOF > "$MOUNT_A/run/php-fpm.conf"
[global]
error_log = "$MOUNT_A/run/php_error.log"
daemonize = no
[www]
listen = "$MOUNT_A/run/php-fpm.sock"
listen.mode = 0660
pm = static
pm.max_children = 5
clear_env = no
EOF

        # --- EXTERNAL WORKSPACE DEPLOYMENT ---
        # 2. Database Initialization
        if [ ! -d "$MOUNT_A/db/mysql" ]; then
            echo "Initializing MariaDB system tables inside writeable slot..."
            mariadb-install-db --datadir="$MOUNT_A/db" --user=$(whoami) --auth-root-authentication-method=normal --skip-test-db >/dev/null 2>&1
        fi

        # 3. Dynamic External WordPress Deployment
        if [ ! -f "$MOUNT_A/www/wp-login.php" ]; then
            WP_ZIP=$(ls "$LAUNCH_DIR"/wordpress-*.zip 2>/dev/null | head -n 1)
            if [ -n "$WP_ZIP" ]; then
                echo "Unpacking external web application payload: $(basename "$WP_ZIP")"
                mkdir -p /tmp/wp_out_$$
                unzip -q "$WP_ZIP" -d /tmp/wp_out_$$
                mv /tmp/wp_out_$$/wordpress/* "$MOUNT_A/www/"
                rm -rf /tmp/wp_out_$$
            else
                echo "WARNING: No external wordpress-*.zip package located in $LAUNCH_DIR"
                echo "Dropping baseline configuration file slot fallback instead..."
            fi
        fi

        # --- START ENGINES ---
        DB_SOCKET="$MOUNT_A/run/mysql.sock"
        cat <<EOF > "$MOUNT_A/run/init.sql"
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE USER IF NOT EXISTS 'nootroot'@'localhost' IDENTIFIED BY '';
GRANT ALL PRIVILEGES ON wordpress.* TO 'nootroot'@'localhost';
FLUSH PRIVILEGES;
EOF
        
        mariadbd --datadir="$MOUNT_A/db" --socket="$DB_SOCKET" --init-file="$MOUNT_A/run/init.sql" --skip-networking &
        MARIADB_PID=$!
        
        echo "Waiting for MariaDB to initialize..."
        until [ -S "$DB_SOCKET" ]; do sleep 1; done

        # Generate localized wp-config.php entirely on the writeable external partition
        if [ ! -f "$MOUNT_A/www/wp-config.php" ] && [ -f "$MOUNT_A/www/wp-login.php" ]; then
            echo "Generating isolated external wp-config.php..."
            cat <<EOF > "$MOUNT_A/www/wp-config.php"
<?php
define('DB_NAME', 'wordpress');
define('DB_USER', 'nootroot');
define('DB_PASSWORD', '');
define('DB_HOST', 'localhost:$DB_SOCKET');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');
\$table_prefix = 'wp_';
define('WP_DEBUG', false);
if ( ! defined( 'ABSPATH' ) ) define( 'ABSPATH', __DIR__ . '/' );
require_once ABSPATH . 'wp-settings.php';
EOF
        fi

        php-fpm -y "$MOUNT_A/run/php-fpm.conf" &
        PHPFPM_PID=$!

        nginx -c "$MOUNT_A/run/nginx.conf" &
        NGINX_PID=$!

        sleep 2
        echo "------------------------------------------------"
        echo "SESSIONS ACTIVE: http://localhost:8080"
        echo "------------------------------------------------"
        echo "If forced to exit prematurely, use Ctrl+C to drop mounts cleanly."
        echo -e -n "\e[31mPress Enter to Shutdown.\e[0m "
        read -r
        echo ""

        kill "$MARIADB_PID" "$PHPFPM_PID" "$NGINX_PID" 2>/dev/null
        
        if fuse2fs -o offset=$(get_off 1),rw,uid=$(id -u),gid=$(id -g) "$0" "$MOUNT_B"; then
            rsync -a --delete --exclude 'lost+found' "$MOUNT_A/" "$MOUNT_B/"
            fusermount -u -z "$MOUNT_B"
        fi
    fi
fi

trap - SIGINT SIGTERM
sync
fusermount -u -z "$MOUNT_A" 2>/dev/null
rm -rf "$MOUNT_A" "$MOUNT_B"
exit 0
THE_STORAGE_ZONE_STARTS_HERE
