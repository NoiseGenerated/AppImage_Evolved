# AppImage_Evolved (ish)

A fully self-contained, zero-root web server appliance packaged as a portable hybrid AppImage. 
Embeds an immutable Nginx, PHP-FPM, and MariaDB infrastructure core alongside isolated, persistent ext4 storage layers, 
allowing complete web applications (like WordPress) to deploy dynamically and run in user land without administrative setup or root access.

---

# Developer Guide: Building the Evolved AppImage

This document outlines the decoupled development workspace environment required before compilation and details how the staging engine 
dynamically handles external web applications alongside isolated user-space storage blocks.

## 1. Quick Build (Automated Staging & Compilation)

To automatically unpack the required binary assets, stage the environment, pull down the latest web application core, and compile the final AppImage execution block, 
run the following command chain from the root of your local workspace directory:

```
git clone https://github.com/NoiseGenerated/AppImage_Evolved && cd AppImage_Evolved && 7z x binaries.7z -o./ && chmod +x *.sh && ./stage_project.sh && ./evolved_builder.sh
```
```bash

If you are staging components manually, your local development directory must match the structure below. 
Your core scripts (`stage_project.sh` and `evolved_builder.sh`) use this layout to construct the pristine, 
read-only SquashFS execution layer while completely ignoring local testing artifacts via `.gitignore`.

```text
.
├── binaries/                                 # Local asset storage (ignored by git tracking)
│   ├── all_files_in_this_folder_came_LinuxBrew
│   ├── even_tho_all_files_are_clean_I_highly_recommend_you_source_them_yourself
│   ├── mariadb-admin
│   ├── mariadbd
│   ├── mariadb-install-db
│   ├── nginx
│   ├── php
│   └── php-fpm
├── binaries.7z                               # Compressed production binary archive
├── evolved_builder.sh                        # Core compilation script (squashfs/padding/slot chain)
├── stage_project.sh                          # Universal staging script (directory assembly & upstream wget)
└── .gitignore                                # Strict exclusion profile protecting repo scale

squashfs-root/
├── etc/                       # Skeleton fallback configuration directory
└── usr/
    ├── bin/
    │   ├── mariadb-admin      # Database management utility
    │   ├── mariadbd           # Core MariaDB database daemon
    │   ├── mariadb-install-db # System table factory initializer
    │   ├── nginx              # High-performance web server binary
    │   ├── php                # CLI PHP interpreter
    │   └── php-fpm            # FastCGI Process Manager binary
    └── lib/
        └── ld-linux-x86-64.so.2 # Embedded system dynamic linker dependency

```

> **Verification:** You can view the [Sandbox Security Scan](https://hybrid-analysis.com/file-collection/6a08b6da4296e68ee90b2e68) for the included asset binaries.

---

## ⚠️ WARNING: Highly Experimental (The "Impossible" Spec)

This architecture is **not extensively tested** and should be considered highly experimental.
Use it with caution and **NOT** in production environments.

### Why does this project even exist?

Because ChatGPT explicitly stated that it was *100% impossible* to implement a portable, persistent storage layer natively inside an AppImage container.

This repository serves as a functional proof-of-concept proving that with a clever hybrid architecture 
(combining a read-only SquashFS server core with user-space FUSE loopback mounts), 
you absolutely *can* run a fully stateful, zero-root web engine entirely in user land.

Since we are actively breaking "impossible" rules here, things might snap during edge-case teardowns. 
If your environment locks up, see the **Emergency Environment Teardown** section below.

---

## Emergency Environment Teardown

If the AppImage crashes or you get "Device or resource busy" errors, your host system might still be holding onto the virtual folders. 
Run this one-liner to force-detach all active vaults and wipe the temporary mount points safely:

```bash
for v in /tmp/vault_*; do [ -d "$v" ] && fusermount -u -z "$v" && rm -rf "$v"; done

```
