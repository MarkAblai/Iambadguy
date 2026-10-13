#!/bin/bash
# CCDC Red Team - deploy cleanup.sh to all student VMs over SSH (root login).
# Run ON THE RED TEAM VM (192.168.4.241).
#   ./deploy_cleanup.sh
# Pushes cleanup.sh to each target and runs it as root to revert every level.
#
# NOTE: A box that already has the Level 5 iptables lockdown applied will DROP
# inbound SSH, so this cannot reach it. Clean those up from the console / QEMU
# guest agent instead (run cleanup.sh there directly).

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/targets.conf"

# Locate the payload whether run from the repo or from /opt/ccdc.
# If CLEANUP_DIR is preset but wrong, fall through to the search instead of
# trusting it blindly.
if [ -z "${CLEANUP_DIR:-}" ] || [ ! -f "${CLEANUP_DIR}/cleanup.sh" ]; then
    CLEANUP_DIR=""
    for cand in "$SELF_DIR/../utils" "$SELF_DIR/../Utils" /opt/ccdc/utils; do
        [ -f "$cand/cleanup.sh" ] && CLEANUP_DIR="$cand" && break
    done
fi
SCRIPT="${CLEANUP_DIR:-}/cleanup.sh"

command -v sshpass >/dev/null 2>&1 || { echo "sshpass not installed - run install_all.sh first"; exit 1; }
[ -f "$SCRIPT" ] || { echo "Payload not found: cleanup.sh (looked in $CLEANUP_DIR)"; exit 1; }

# Lab options: skip host-key prompts, force password auth, short timeout.
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
-o PubkeyAuthentication=no -o PreferredAuthentications=password -o ConnectTimeout=10"

for ip in "${TARGETS[@]}"; do
    echo "[*] cleanup -> $ip"
    if sshpass -p "$SSH_PASS" scp $SSH_OPTS "$SCRIPT" root@"$ip":/tmp/ \
       && sshpass -p "$SSH_PASS" ssh $SSH_OPTS root@"$ip" "bash /tmp/cleanup.sh"; then
        echo "[+] $ip done"
    else
        echo "[!] $ip FAILED (locked down? clean from console instead)"
    fi
done
