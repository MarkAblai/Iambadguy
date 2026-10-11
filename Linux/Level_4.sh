#!/bin/bash
# CCDC Red Team - Level 4
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.

# --- Part A: break postfix with a small main.cf change ---
break_postfix() {
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
    systemctl stop dovecot 2>/dev/null
    systemctl disable dovecot 2>/dev/null

    # Purge packages (removes config owned by the packages).
    apt-get purge -y 'dovecot-*'

    # Wipe anything left so they rebuild from the ground up.
    rm -rf /etc/dovecot /var/lib/dovecot
}

# --- Tasks ---
break_postfix
remove_dovecot
