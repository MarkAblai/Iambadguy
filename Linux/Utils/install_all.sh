#!/bin/bash
# CCDC Red Team - installer
# Run ON THE RED TEAM VM. Stages all five Linux attack scripts into
# /opt/ccdc/attacks/ so they can be pushed to the blue VMs via the
# QEMU guest agent at each level's scheduled time.
#
#   sudo ./install_all.sh
#
# Re-running pulls the latest from the repo (safe to run again).

set -euo pipefail

REPO="https://github.com/MarkAblai/Iambadguy.git"
BRANCH="main"
SRC_SUBDIR="Linux/Attacks"
STAGE="/opt/ccdc/attacks"
CLONE_TMP="/opt/ccdc/.repo"

# Need git; install if missing.
if ! command -v git >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y git
fi

mkdir -p /opt/ccdc

# Fresh clone each run so the staged scripts always match the repo.
rm -rf "$CLONE_TMP"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$CLONE_TMP"

# Copy just the attack scripts into the staging dir.
mkdir -p "$STAGE"
cp -f "$CLONE_TMP/$SRC_SUBDIR"/Level_*.sh "$STAGE"/
chmod +x "$STAGE"/Level_*.sh

rm -rf "$CLONE_TMP"

echo "Staged to $STAGE:"
ls -1 "$STAGE"/Level_*.sh
