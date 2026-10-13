#!/bin/bash
# CCDC Red Team - cleanup / reset
# Run as root ON A TARGET VM (via console or QEMU guest agent, which runs as
# root by default). Reverses everything Level_1..Level_5 did so students get a
# clean system to start from.
#
#   sudo ./cleanup.sh
#
# Comment out a function call at the bottom to skip undoing that level.
#
# Notes:
#   * Best effort: every step is guarded so it is safe to run even if a given
#     attack was never deployed, and safe to run more than once.
#   * Level 4 purged the dovecot packages AND deleted their config. Those are
#     reinstalled here, which restores the PACKAGE DEFAULT config, not any
#     custom config that existed before. Needs apt / network access. For a
#     byte-for-byte original image, restore a VM snapshot instead.

echo "[*] CCDC cleanup starting on $(hostname) ..."

# -------------------------------------------------------------------------
# Helper: strip an appended block from a file, from a START marker line to an
# END marker line (inclusive), including the single blank line that precedes
# the START marker. Used to undo the /etc/bash.bashrc edits.
# -------------------------------------------------------------------------
remove_block() {
    local file="$1" start_re="$2" end_re="$3"
    [ -f "$file" ] || return 0
    grep -qE "$start_re" "$file" || return 0

    local tmp
    tmp="$(mktemp)" || return 1
    awk -v s="$start_re" -v e="$end_re" '
        function flush() { if (have) { print buf; have=0 } }
        inblk==0 && $0 ~ s { have=0; inblk=1; next }   # drop buffered blank before block
        inblk==1            { if ($0 ~ e) inblk=0; next }
        /^$/                { flush(); buf=$0; have=1; next }
                            { flush(); print }
        END                 { flush() }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

# =========================================================================
# Level 5 reversal FIRST: restore network/firewall so connectivity is back
# immediately (important if this is run over a link that the lockdown killed).
# =========================================================================
undo_level5() {
    echo "[*] Undo Level 5: network lockdown + Enter override"

    # --- Part A: remove the boot-time iptables lockdown and reset iptables ---
    systemctl disable --now ccdc-lockdown.service 2>/dev/null
    rm -f /etc/systemd/system/ccdc-lockdown.service
    rm -f /usr/local/sbin/ccdc-lockdown.sh
    systemctl daemon-reload 2>/dev/null

    if command -v iptables >/dev/null 2>&1; then
        # Set permissive policies BEFORE flushing so we never sit at DROP.
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -F
        iptables -X
        iptables -t nat -F;    iptables -t nat -X
        iptables -t mangle -F; iptables -t mangle -X
    fi

    # --- Part B: remove the Enter (C-m) readline override from bash.bashrc ---
    remove_block /etc/bash.bashrc '^# ccdc-enter-override' '^bind -x'
}

# =========================================================================
# Level 1 reversal: restore apache + open firewall back up.
# =========================================================================
undo_level1() {
    echo "[*] Undo Level 1: apache + port 80"

    if command -v ufw >/dev/null 2>&1; then
        ufw delete deny 80/tcp 2>/dev/null
        # Original baseline has ufw inactive; disabling restores that and
        # removes the deny-80 rule regardless.
        ufw --force disable 2>/dev/null
    fi

    systemctl start apache2 2>/dev/null
}

# =========================================================================
# Level 2 reversal: remove mail-stop cron, restore /var/mail, restart mail.
# =========================================================================
undo_level2() {
    echo "[*] Undo Level 2: mail-stop cron + /var/mail ownership"

    # --- Part A: remove the cron job and its helper ---
    rm -f /etc/cron.d/ccdc-mail
    rm -f /usr/local/bin/mailstop.sh

    # --- Part B: restore /var/mail ownership/perms to the Debian default ---
    if [ -d /var/mail ]; then
        # Directory: root:mail, setgid, 2775.
        chown root:mail /var/mail 2>/dev/null
        chmod 2775 /var/mail 2>/dev/null

        # Each mailbox is named after its user: owner:mail, 660.
        for mbox in /var/mail/*; do
            [ -f "$mbox" ] || continue
            local u
            u="$(basename "$mbox")"
            if id "$u" >/dev/null 2>&1; then
                chown "$u":mail "$mbox" 2>/dev/null
                chmod 660 "$mbox" 2>/dev/null
            fi
        done
    fi

    systemctl restart postfix 2>/dev/null
    systemctl restart dovecot 2>/dev/null
}

# =========================================================================
# Level 3 reversal: remove defacement, cow cron, and the `cat` override.
# =========================================================================
undo_level3() {
    echo "[*] Undo Level 3: defacement + cow cron + cat override"

    # --- Part A: remove the index.html that shadowed OpenCart (only ours) ---
    local webroot
    webroot="$(grep -rhiE '^[[:space:]]*DocumentRoot' /etc/apache2/sites-enabled/ 2>/dev/null \
               | awk '{print $2}' | head -n1)"
    webroot="${webroot:-/var/www/html}"
    if [ -f "$webroot/index.html" ] && grep -q 'HACKED' "$webroot/index.html" 2>/dev/null; then
        rm -f "$webroot/index.html"
    fi

    # --- Part B: remove the cow-wall cron and its assets ---
    rm -f /etc/cron.d/ccdc-cow
    rm -f /usr/local/bin/cowwall.sh
    rm -f /usr/local/share/ccdc-cow.txt

    # --- Part C: remove the cat() override from bash.bashrc ---
    remove_block /etc/bash.bashrc '^# ccdc-cat-override' '^}$'
}

# =========================================================================
# Level 4 reversal: fix postfix inet_interfaces, reinstall dovecot.
# =========================================================================
undo_level4() {
    echo "[*] Undo Level 4: postfix inet_interfaces + dovecot"

    # --- Part A: restore postfix to listen on all interfaces ---
    if command -v postconf >/dev/null 2>&1; then
        postconf -e 'inet_interfaces = all'
        systemctl restart postfix 2>/dev/null
        systemctl enable postfix 2>/dev/null
    fi

    # --- Part B: reinstall dovecot (package default config) ---
    # Level 4 purged the packages and wiped /etc/dovecot + /var/lib/dovecot,
    # so there is nothing to restore except by reinstalling.
    if ! command -v dovecot >/dev/null 2>&1; then
        apt-get update -y
        apt-get install -y dovecot-core dovecot-imapd dovecot-pop3d
    fi
    systemctl enable dovecot 2>/dev/null
    systemctl restart dovecot 2>/dev/null
}

# -------------------------------------------------------------------------
# Tasks (order matters: restore connectivity first, then services/configs).
# Comment out any call to skip undoing that level.
# -------------------------------------------------------------------------
undo_level5
undo_level1
undo_level2
undo_level3
undo_level4

echo "[+] CCDC cleanup complete on $(hostname)."
echo "    Open a NEW shell to clear any active cat/Enter overrides in this session."
