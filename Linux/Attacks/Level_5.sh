#!/bin/bash
# CCDC Red Team - Level 5 (final)
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.
# Both parts survive a VM reboot.

LOCKDOWN_BIN=/usr/local/sbin/ccdc-lockdown.sh
LOCKDOWN_UNIT=/etc/systemd/system/ccdc-lockdown.service

# --- Part A: deny-all at the iptables layer, reapplied on every boot ---
lockdown_iptables() {
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
    "$LOCKDOWN_BIN"
}

# --- Part B: make Enter print a cow instead of running the command ---
break_enter() {
    # Rebind Enter (C-m) via readline so it prints the cow and clears the line
    # instead of accept-line. Ctrl+J (C-j) stays bound to accept-line, so that
    # is the escape hatch students have to find. Lives in /etc/bash.bashrc, so
    # it reapplies in every new interactive shell, including after a reboot.
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
lockdown_iptables
break_enter
