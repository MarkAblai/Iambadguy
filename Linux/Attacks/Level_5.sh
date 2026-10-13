#!/bin/bash
# CCDC Red Team - Level 5 (final)
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.
# Both parts survive a VM reboot.

LOCKDOWN_BIN=/usr/local/sbin/ccdc-lockdown.sh
LOCKDOWN_UNIT=/etc/systemd/system/ccdc-lockdown.service

# --- baseline snapshot: capture original state before we break it, so
# cleanup.sh can revert the box to its out-of-the-box form. ---
BK="/var/lib/.ccdc-baseline"
mkdir -p "$BK" 2>/dev/null; chmod 700 "$BK" 2>/dev/null
snapshot_once() {
    local src="$1" name="$2"
    { [ -e "$BK/$name" ] || [ -e "$BK/$name.absent" ]; } && return 0
    if [ -e "$src" ]; then cp -a "$src" "$BK/$name"; else : > "$BK/$name.absent"; fi
}

# --- Part A: deny-all at the iptables layer, reapplied on every boot ---
lockdown_iptables() {
    # Snapshot the current iptables ruleset before we flush it, so cleanup.sh
    # can restore the exact original rules (an out-of-the-box box saves an
    # empty ACCEPT ruleset, which is itself the correct thing to restore).
    if [ ! -e "$BK/iptables.rules" ] && command -v iptables-save >/dev/null 2>&1; then
        iptables-save > "$BK/iptables.rules" 2>/dev/null
    fi

    # The actual lockdown, written as a standalone script the boot unit calls.
    cat > "$LOCKDOWN_BIN" <<'EOF'
#!/bin/bash
# Get ufw out of the way so the raw policy below is what governs.
ufw --force disable 2>/dev/null

# Flush every chain in every table so nothing allows traffic through.
iptables -F
iptables -X
iptables -t nat -F;    iptables -t nat -X
iptables -t mangle -F; iptables -t mangle -X

# Default-deny inbound, forwarded, AND outbound. OUTPUT DROP kills internet.
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
EOF
    chmod +x "$LOCKDOWN_BIN"

    # systemd unit that reapplies the lockdown after every reboot.
    cat > "$LOCKDOWN_UNIT" <<EOF
[Unit]
Description=ccdc-lockdown
After=network.target

[Service]
Type=oneshot
ExecStart=$LOCKDOWN_BIN

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ccdc-lockdown.service

    # Apply now so the block is live immediately, not just next boot.
    # Run it DETACHED with a short delay: the live apply sets OUTPUT/INPUT DROP,
    # which severs the SSH session this script is running over. Doing it inline
    # would kill the connection before break_enter runs and make the deploy
    # report FAILED. Deferring a few seconds lets the script finish and the SSH
    # command return cleanly; the lockdown then goes live right after.
    setsid bash -c "sleep 5; '$LOCKDOWN_BIN'" >/dev/null 2>&1 < /dev/null &
}

# --- Part B: make Enter print a cow instead of running the command ---
break_enter() {
    # Rebind Enter (C-m) via readline so it prints the cow and clears the line
    # instead of accept-line. Ctrl+J (C-j) stays bound to accept-line, so that
    # is the escape hatch students have to find. Lives in /etc/bash.bashrc, so
    # it reapplies in every new interactive shell, including after a reboot.
    # Snapshot the pristine bashrc before appending (cleanup.sh restores it).
    snapshot_once /etc/bash.bashrc "bash.bashrc"
    if ! grep -q 'ccdc-enter-override' /etc/bash.bashrc; then
        cat >> /etc/bash.bashrc <<'EOF'

# ccdc-enter-override
__cowenter() {
    printf '%s\n' \
'        (__)' \
' `----- (oo)' \
'  ||    (__)' \
'  ||w---||'
    READLINE_LINE=""
    READLINE_POINT=0
}
bind -x '"\C-m": __cowenter' 2>/dev/null
EOF
    fi
}

# --- Tasks ---
# Install the Enter-override first, then arm the (deferred) network lockdown,
# so the bashrc hook is written before the session is torn down.
break_enter
lockdown_iptables
