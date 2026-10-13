#!/bin/bash
# CCDC Red Team - installer
# Run ON THE RED TEAM VM (192.168.4.241).
#   sudo ./install_all.sh
#
# Stages the attack payloads and the SSH deploy scripts under /opt/ccdc and
# installs the tools they need. Re-run anytime to pull the latest from the repo.

set -euo pipefail

REPO="https://github.com/MarkAblai/Iambadguy.git"
BRANCH="main"
BASE="/opt/ccdc"
CLONE_TMP="$BASE/.repo"

# Dependencies: git to pull, sshpass to push over SSH with a password.
need=()
command -v git     >/dev/null 2>&1 || need+=(git)
command -v sshpass >/dev/null 2>&1 || need+=(sshpass)
if [ "${#need[@]}" -gt 0 ]; then
    apt-get update -y
    apt-get install -y "${need[@]}"
fi

mkdir -p "$BASE"

# Fresh clone each run so staged files always match the repo.
rm -rf "$CLONE_TMP"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$CLONE_TMP"

# Stage payloads and deploy scripts as siblings under /opt/ccdc.
mkdir -p "$BASE/attacks" "$BASE/deploy" "$BASE/utils"
cp -f "$CLONE_TMP/Linux/Attacks"/Level_*.sh        "$BASE/attacks"/
cp -f "$CLONE_TMP/Linux/Deploy"/deploy_level*.sh   "$BASE/deploy"/
cp -f "$CLONE_TMP/Linux/Deploy"/deploy_cleanup.sh  "$BASE/deploy"/
cp -f "$CLONE_TMP/Linux/Deploy"/targets.conf       "$BASE/deploy"/
cp -f "$CLONE_TMP/Linux/Utils"/cleanup.sh          "$BASE/utils"/
chmod +x "$BASE/attacks"/Level_*.sh "$BASE/deploy"/deploy_level*.sh \
         "$BASE/deploy"/deploy_cleanup.sh "$BASE/utils"/cleanup.sh
chmod 600 "$BASE/deploy/targets.conf"   # holds the root password

rm -rf "$CLONE_TMP"

echo "Staged under $BASE:"
echo "  payloads ($BASE/attacks):"
ls -1 "$BASE/attacks"/Level_*.sh
echo "  deploy   ($BASE/deploy):"
ls -1 "$BASE/deploy"/deploy_level*.sh
echo "  cleanup  ($BASE/utils):"
ls -1 "$BASE/utils"/cleanup.sh
echo
echo "Deploy a level to all student VMs, e.g.:"
echo "  cd $BASE/deploy && ./deploy_level1.sh"
echo
echo "Revert everything (clean systems) with:"
echo "  cd $BASE/deploy && ./deploy_cleanup.sh"
