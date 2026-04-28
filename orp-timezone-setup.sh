#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# orp-timezone-setup.sh — ORP ENGINE TIMEZONE CONFIGURATION
# ──────────────────────────────────────────────────────────────────
# DESC: Configures system timezone (Asia/Manila) for WSL2/Linux
#
# USAGE: chmod +x orp-timezone-setup.sh && ./orp-timezone-setup.sh
#
# TARGET_TIMEZONE (UPPERCASE):
#   Asia/Manila — Default for Philippine LGUs
#
# SETS:
#   /etc/localtime — System timezone symlink
#   TZ in ~/.bashrc — Environment variable for new sessions
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

TARGET_TZ="Asia/Manila"
LOG_FILE="$HOME/orp-timezone-setup.log"

# ──────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────

ok()   { printf "[✔] %s\n" "$1"; }
info() { printf "[*] %s\n" "$1"; }
warn() { printf "[!] %s\n" "$1"; }

banner() {
  cat <<EOF

╔═════════════════════════════════════════════════════════════════════╗
║  $1
╚═════════════════════════════════════════════════════════════════════╝

EOF
}

section_header() {
  printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "  %s\n" "$1"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
}

# ──────────────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────────────

clear
banner "ORP ENGINE — TIMEZONE CONFIGURATION (WSL2/Linux)"

printf "  TARGET_TIMEZONE:  %s\n\n" "$TARGET_TZ"

section_header "STEP 1 — SETTING SYSTEM TIMEZONE"

info "Setting /etc/localtime to $TARGET_TZ..."

if sudo ln -sf "/usr/share/zoneinfo/$TARGET_TZ" /etc/localtime 2>/dev/null; then
    ok "System timezone configured"
else
    warn "Could not set system timezone (may need sudo password or permissions)"
fi

# Set environment variable
section_header "STEP 2 — CONFIGURING SHELL ENVIRONMENT"

if ! grep -q "export TZ=" "$HOME/.bashrc" 2>/dev/null; then
    echo "export TZ=\"$TARGET_TZ\"" >> "$HOME/.bashrc"
    ok "Added TZ to ~/.bashrc for future sessions"
else
    ok "TZ already in ~/.bashrc"
fi

# Export for current session
export TZ="$TARGET_TZ"

# Display current time
section_header "STEP 3 — VERIFICATION"

CURRENT_TIME=$(date)
ok "Current timezone: $CURRENT_TIME"

# Log the configuration
section_header "LOGGING"

{
    printf "═══════════════════════════════════════════════════════════\n"
    printf "Timezone Setup Log\n"
    printf "═══════════════════════════════════════════════════════════\n"
    printf "Timestamp (UTC):  %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf "TARGET_TIMEZONE:  %s\n" "$TARGET_TZ"
    printf "System time:      %s\n" "$CURRENT_TIME"
    printf "═══════════════════════════════════════════════════════════\n"
} >> "$LOG_FILE"

ok "Timezone setup complete"
ok "Log: $LOG_FILE"
