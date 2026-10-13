#!/bin/bash
# CCDC Red Team - cleanup / reset
# Run as root ON A TARGET VM (via console or QEMU guest agent, which runs as
# root by default). Reverts everything Level_1..Level_5 did so students get a
# clean, out-of-the-box system to start from.
#
#   sudo ./cleanup.sh
#
# Comment out a function call at the bottom to skip undoing that level.
#
# How the revert works:
#   The attack scripts snapshot each piece of ORIGINAL state into a hidden
#   baseline store (/var/lib/.ccdc-baseline) BEFORE they damage it. This script
#   restores from that store for a byte-exact revert, and falls back to a
#   best-effort reconstruction when a snapshot is missing (e.g. a box hit by an
#   older attack script that predates the baseline store). The store itself is
#   removed at the end so a cleaned box carries no leftover artifacts.

BK="/var/lib/.ccdc-baseline"
echo "[*] CCDC cleanup starting on $(hostname) ..."

# -------------------------------------------------------------------------
# Helper: strip an appended block from a file, from a START marker line to an
# END marker line (inclusive), including the single blank line that precedes
# the START marker. Used only as a FALLBACK for the /etc/bash.bashrc edits
# when no baseline snapshot of the file exists.
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
    echo "[*] Undo Level 5: network lockdown"

    # Remove the boot-time iptables lockdown service + script.
    systemctl disable --now ccdc-lockdown.service 2>/dev/null
    rm -f /etc/systemd/system/ccdc-lockdown.service
    rm -f /usr/local/sbin/ccdc-lockdown.sh
    systemctl daemon-reload 2>/dev/null

    if command -v iptables >/dev/null 2>&1; then
        if [ -f "$BK/iptables.rules" ] && command -v iptables-restore >/dev/null 2>&1; then
            # Byte-exact restore of the original ruleset.
            iptables-restore < "$BK/iptables.rules"
        else
            # Fallback: reset to the default open state (ACCEPT + empty chains).
            # Set permissive policies BEFORE flushing so we never sit at DROP.
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            iptables -F
            iptables -X
            iptables -t nat -F;    iptables -t nat -X
            iptables -t mangle -F; iptables -t mangle -X
        fi
    fi
    # (The /etc/bash.bashrc Enter override is reverted by restore_bashrc below.)
}

# =========================================================================
# Level 1 reversal: restore apache + open firewall back up.
# =========================================================================
undo_level1() {
    echo "[*] Undo Level 1: apache + port 80"

    if command -v ufw >/dev/null 2>&1; then
        ufw delete deny 80/tcp 2>/dev/null
        ufw --force disable 2>/dev/null
        # If the attack installed ufw, purge it to match the original box.
        if [ -e "$BK/ufw_installed_by_ccdc" ]; then
            apt-get purge -y ufw 2>/dev/null
        fi
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

    # --- Part B: restore /var/mail ownership/perms ---
    if [ -f "$BK/var_mail_meta" ]; then
        # Byte-exact: replay the snapshotted mode/owner/group for each path.
        while IFS=$'\t' read -r mode uid gid path; do
            [ -e "$path" ] || continue
            chown "$uid:$gid" "$path" 2>/dev/null
            chmod "$mode" "$path" 2>/dev/null
        done < "$BK/var_mail_meta"
    elif [ -d /var/mail ]; then
        # Fallback: Debian defaults (root:mail 2775 dir, owner:mail 660 boxes).
        chown root:mail /var/mail 2>/dev/null
        chmod 2775 /var/mail 2>/dev/null
        for mbox in /var/mail/*; do
            [ -f "$mbox" ] || continue
            local u; u="$(basename "$mbox")"
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
# Level 3 reversal: restore index page, remove cow cron (+ cat override via
# restore_bashrc).
# =========================================================================
undo_level3() {
    echo "[*] Undo Level 3: defacement + cow cron"

    # --- Part A: restore the original index.html ---
    local webroot
    if [ -f "$BK/webroot_path" ]; then
        webroot="$(cat "$BK/webroot_path")"
    else
        webroot="$(grep -rhiE '^[[:space:]]*DocumentRoot' /etc/apache2/sites-enabled/ 2>/dev/null \
                   | awk '{print $2}' | head -n1)"
        webroot="${webroot:-/var/www/html}"
    fi

    if [ -e "$BK/index.html" ]; then
        # There WAS an original index.html: put it back exactly.
        cp -a "$BK/index.html" "$webroot/index.html"
    elif [ -e "$BK/index.html.absent" ]; then
        # There was none originally: removing ours un-shadows index.php.
        rm -f "$webroot/index.html"
    else
        # No snapshot (old attack): only remove the file if it is our cow.
        if [ -f "$webroot/index.html" ] && grep -q 'HACKED' "$webroot/index.html" 2>/dev/null; then
            rm -f "$webroot/index.html"
        fi
    fi

    # --- Part B: remove the cow-wall cron and its assets ---
    rm -f /etc/cron.d/ccdc-cow
    rm -f /usr/local/bin/cowwall.sh
    rm -f /usr/local/share/ccdc-cow.txt
    # (The /etc/bash.bashrc cat override is reverted by restore_bashrc below.)
}

# =========================================================================
# Level 4 reversal: restore postfix main.cf, reinstall + restore dovecot.
# =========================================================================
undo_level4() {
    echo "[*] Undo Level 4: postfix inet_interfaces + dovecot"

    # --- Part A: restore postfix main.cf ---
    if [ -f "$BK/postfix_main.cf" ]; then
        cp -a "$BK/postfix_main.cf" /etc/postfix/main.cf
    elif command -v postconf >/dev/null 2>&1; then
        postconf -e 'inet_interfaces = all'   # fallback: package default
    fi
    systemctl restart postfix 2>/dev/null
    systemctl enable postfix 2>/dev/null

    # --- Part B: reinstall dovecot and restore its original config ---
    if ! command -v dovecot >/dev/null 2>&1; then
        local pkgs="dovecot-core dovecot-imapd dovecot-pop3d"
        if [ -s "$BK/dovecot_pkgs" ]; then
            pkgs="$(tr '\n' ' ' < "$BK/dovecot_pkgs")"   # the exact original set
        fi
        apt-get update -y
        apt-get install -y $pkgs
    fi
    # Overlay the original config trees on top of the reinstalled defaults.
    [ -f "$BK/dovecot_etc.tar" ] && tar -xpf "$BK/dovecot_etc.tar" -C /
    [ -f "$BK/dovecot_var.tar" ] && tar -xpf "$BK/dovecot_var.tar" -C /

    systemctl enable dovecot 2>/dev/null
    systemctl restart dovecot 2>/dev/null
}

# =========================================================================
# Shared: restore /etc/bash.bashrc once (reverts BOTH the Level 3 cat override
# and the Level 5 Enter override in one shot).
# =========================================================================
restore_bashrc() {
    echo "[*] Restore /etc/bash.bashrc"
    if [ -f "$BK/bash.bashrc" ]; then
        cp -a "$BK/bash.bashrc" /etc/bash.bashrc
    else
        # Fallback for boxes with no snapshot: surgically strip both blocks.
        remove_block /etc/bash.bashrc '^# ccdc-enter-override' '^bind -x'
        remove_block /etc/bash.bashrc '^# ccdc-cat-override'   '^}$'
    fi
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
restore_bashrc

# Remove the baseline store so a cleaned box has no leftover artifacts.
rm -rf "$BK"

echo "[+] CCDC cleanup complete on $(hostname)."
echo "    Open a NEW shell to clear any active cat/Enter overrides in this session."
