#!/bin/bash
# CCDC Red Team - Level 4
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.

# --- baseline snapshot: capture original state before we break it, so
# cleanup.sh can revert the box to its out-of-the-box form. ---
BK="/var/lib/.ccdc-baseline"
mkdir -p "$BK" 2>/dev/null; chmod 700 "$BK" 2>/dev/null
snapshot_once() {
    local src="$1" name="$2"
    { [ -e "$BK/$name" ] || [ -e "$BK/$name.absent" ]; } && return 0
    if [ -e "$src" ]; then cp -a "$src" "$BK/$name"; else : > "$BK/$name.absent"; fi
}

# --- Part A: break postfix with a small main.cf change ---
break_postfix() {
    # Snapshot the pristine main.cf so cleanup.sh restores the exact original,
    # not just a guessed 'inet_interfaces = all'.
    snapshot_once /etc/postfix/main.cf "postfix_main.cf"

    # inet_interfaces must list local interfaces. Pointing it at an IP that
    # isn't on the box makes postfix fail to start:
    #   fatal: parameter inet_interfaces: no local interface found for 10.255.255.255
    # One line in /etc/postfix/main.cf. Fix = set it back to 'all'.
    postconf -e 'inet_interfaces = 10.255.255.255'

    # Apply now so the service is down when students get the box.
    systemctl restart postfix
}

# --- Part B: remove dovecot entirely (service + config) ---
remove_dovecot() {
    # Snapshot BEFORE destroying: the exact installed dovecot packages and both
    # config trees, so cleanup.sh reinstalls the same packages and restores the
    # original config (not just package defaults).
    if [ ! -e "$BK/dovecot_pkgs" ]; then
        dpkg -l 2>/dev/null | awk '/^ii/ && $2 ~ /^dovecot/ {print $2}' > "$BK/dovecot_pkgs"
    fi
    [ ! -e "$BK/dovecot_etc.tar" ] && [ -d /etc/dovecot ] \
        && tar -cpf "$BK/dovecot_etc.tar" -C / etc/dovecot 2>/dev/null
    [ ! -e "$BK/dovecot_var.tar" ] && [ -d /var/lib/dovecot ] \
        && tar -cpf "$BK/dovecot_var.tar" -C / var/lib/dovecot 2>/dev/null

    systemctl stop dovecot 2>/dev/null
    systemctl disable dovecot 2>/dev/null

    # Purge packages (removes config owned by the packages). apt treats a name
    # containing regex chars as a POSIX regex, so anchor it with '^dovecot' to
    # match every dovecot-* package explicitly rather than relying on the
    # accidental substring match of a bare 'dovecot-*'.
    apt-get purge -y '^dovecot'

    # Wipe anything left so they rebuild from the ground up.
    rm -rf /etc/dovecot /var/lib/dovecot
}

# --- Tasks ---
break_postfix
remove_dovecot
