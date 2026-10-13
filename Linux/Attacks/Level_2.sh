#!/bin/bash
# CCDC Red Team - Level 2
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.
 
# Confirm these against your test VM output:
#   systemctl list-units --type=service --state=running | grep -iE 'postfix|dovecot|exim|sendmail|opensmtpd'
MAIL_SERVICES="postfix dovecot"
 
# --- Part A: cron job that stops the mail services ---
install_mail_stop_cron() {
    # Small helper script the cron job calls
    cat > /usr/local/bin/mailstop.sh <<EOF
#!/bin/bash
systemctl stop $MAIL_SERVICES
EOF
    chmod +x /usr/local/bin/mailstop.sh
 
    # Drop it in /etc/cron.d - easy to find, as requested.
    # Runs every 2 minutes so a student restart gets killed again.
    cat > /etc/cron.d/ccdc-mail <<'EOF'
*/2 * * * * root /usr/local/bin/mailstop.sh
EOF
    chmod 644 /etc/cron.d/ccdc-mail
}
 
# --- Part B: break /var/mail ownership so mail can't be delivered ---
break_mail_ownership() {
    # Give the whole mail spool to a non-mail user so the MDA can't write to it.
    # root:root with no group/other access breaks delivery cleanly.
    chown -R root:root /var/mail
    chmod -R 700 /var/mail
}
 
# --- Tasks ---
install_mail_stop_cron
break_mail_ownership
 
