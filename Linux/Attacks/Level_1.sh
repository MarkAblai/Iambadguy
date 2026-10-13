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
 
    # 'yes' auto-answers the "proceed?" prompt when enabling UFW
    yes | ufw enable
    ufw deny 80/tcp
    ufw reload
}
 
# --- Tasks ---
stop_apache
block_port_80
 
