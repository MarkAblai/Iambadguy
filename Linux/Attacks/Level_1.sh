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
 
