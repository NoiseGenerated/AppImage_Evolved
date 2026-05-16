#!/bin/bash
# ==============================================================================
# Project: AppImage_Evolved
# Author: NoiseGenerated
# GitHub: https://github.com/NoiseGenerated/AppImage_Evolved
#
# Description:
#   A fully self-contained, zero-root web server stack (Nginx, PHP-FPM, MariaDB)
#   packaged as a portable AppImage. Utilizes user-space FUSE filesystems to
#   mount persistent, writeable ext4 storage slots natively in user land.
#
# License: MIT License
#   Copyright (c) 2026 NoiseGenerated
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files...
# ==============================================================================

APP_NAME="Evolved.AppImage"
SLOT_SIZE_MB=500
RUNTIME_SOURCE="evolved_runtime.sh"
ALIGN=4096

pad_file() {
    local file=$1
    local size=$(stat -c%s "$file")
    local mod=$(( size % ALIGN ))
    if [ $mod -ne 0 ]; then
        local pad=$(( ALIGN - mod ))
        dd if=/dev/zero bs=1 count=$pad >> "$file" 2>/dev/null
    fi
}

# 1. Clean up
echo "Cleaning old artifacts..."
rm -f slot*.img app_code.sqfs "$APP_NAME"

# 2. Create the Code Layer (SquashFS)
echo "Compressing Staff and Master Files..."
mksquashfs squashfs-root app_code.sqfs -noappend -processors $(nproc)

# 3. Create the 5 storage slots
echo "Creating 2.5GB of blank storage slots..."
MY_UID=$(id -u)
MY_GID=$(id -g)

for i in {0..4}; do
    truncate -s "${SLOT_SIZE_MB}M" "slot$i.img"
    
    # 1. Create the filesystem with specific features for FUSE
    # -E root_owner sets the UID/GID during creation (cleaner than debugfs)
    # -O ^has_journal removes the journal to stop the fuse2fs warnings
    mkfs.ext4 -L "VAULT_$i" \
              -E root_owner=$MY_UID:$MY_GID \
              -O ^has_journal \
              -F "slot$i.img" >/dev/null 2>&1
    
    # 2. Force a filesystem check to "seal" the metadata
    e2fsck -y "slot$i.img" >/dev/null 2>&1
done
# 4. Assembly with Padding
echo "Assembling the final binary: $APP_NAME"

# Get header
HEADER_LINES=$(grep -a -n "^THE_STORAGE_ZONE_STARTS_HERE$" "$RUNTIME_SOURCE" | tail -n 1 | cut -d: -f1)
head -n "$HEADER_LINES" "$RUNTIME_SOURCE" > "$APP_NAME"
pad_file "$APP_NAME"

# Add SquashFS
cat app_code.sqfs >> "$APP_NAME"
pad_file "$APP_NAME"

# Add Slots
cat slot0.img slot1.img slot2.img slot3.img slot4.img >> "$APP_NAME"

# 5. Finalize
chmod +x "$APP_NAME"
rm app_code.sqfs slot*.img

echo "------------------------------------------------"
echo "SUCCESS! $APP_NAME is aligned and ready."
echo  Run: ./Evolved.AppImage
echo "------------------------------------------------"

exit 0
