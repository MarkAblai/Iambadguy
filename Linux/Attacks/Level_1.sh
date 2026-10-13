#!/bin/bash
# CCDC Red Team - Level 1
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.
 
stop_apache() {
    systemctl stop apache2
}
 
block_port_80() {
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y ufw
        # Record that WE installed ufw so cleanup.sh can purge it and restore
        # the original out-of-the-box state (no ufw present).
        mkdir -p /var/lib/.ccdc-baseline && chmod 700 /var/lib/.ccdc-baseline
        : > /var/lib/.ccdc-baseline/ufw_installed_by_ccdc
    fi
 
    # Allow SSH (22) BEFORE enabling UFW. Enabling UFW applies its default
    # incoming=deny policy, which would otherwise drop the live SSH session
    # running this script and block every later deploy_levelN.sh (port 22).
    # We only want to block port 80, so keep 22 open.
    ufw allow 22/tcp

    # 'yes' auto-answers the "proceed?" prompt when enabling UFW
    yes | ufw enable
    ufw deny 80/tcp
    ufw reload
}
 
# --- Tasks ---
stop_apache
block_port_80
 
