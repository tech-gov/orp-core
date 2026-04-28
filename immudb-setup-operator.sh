#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# immudb-setup-operator.sh — ORP ENGINE immudb OPERATOR DATABASE SETUP
# ──────────────────────────────────────────────────────────────────
# DESC: Creates immudb operator database and user, tests connection,
#       writes credentials to ~/.identity/db_secrets.env
#
# USAGE: chmod +x immudb-setup-operator.sh && ./immudb-setup-operator.sh
#
# RUN:   ONCE after immudb_setup.sh. Idempotent — re-running will
#        skip creation if database and user already exist.
#
# CREDENTIALS (UPPERCASE) WRITTEN TO ~/.identity/db_secrets.env:
#   IMMUDB_USER — Operator username
#   IMMUDB_DB   — Database name
#
# SECURITY NOTE: immudb PASSWORD is NOT stored. It is prompted
#                interactively at each engine startup via Python
#                getpass() and kept in RAM only.
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

BIN_DIR="${BIN_DIR:-$HOME/bin}"
IMMUD_BIN="$BIN_DIR/immudb"
IMMUADMIN="$BIN_DIR/immuadmin"
IMMUCLIENT="$BIN_DIR/immuclient"
DATA_DIR="${DATA_DIR:-$HOME/.orp_vault/data}"
LOG_FILE="$HOME/.orp_vault/immudb.log"

# ──────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────

ok()      { printf "[✔] %s\n" "$1"; }
info()    { printf "[*] %s\n" "$1"; }
warn()    { printf "[!] %s\n" "$1"; }
die()     { printf "[✘] ERROR: %s\n" "$1" >&2; exit 1; }
hint()    { printf "    %s\n" "$1"; }

banner() {
  cat <<EOF

╔═════════════════════════════════════════════════════════════════════╗
║  $1
║  $2
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
banner "ORP ENGINE — immudb OPERATOR DATABASE SETUP" \
       "Immutable Audit Vault Configuration"

printf "  DATA_DIRECTORY:  %s\n" "$DATA_DIR"
printf "  LOG_FILE:        %s\n\n" "$LOG_FILE"

printf "  This script creates a dedicated database and operator user\n"
printf "  inside immudb. The operator password is set interactively\n"
printf "  and NEVER stored on disk — only in the running immudb instance.\n\n"

mkdir -p "$DATA_DIR" "$(dirname "$LOG_FILE")"

# Verify binaries
section_header "STEP 1 — BINARY VERIFICATION"

for cmd in "$IMMUD_BIN" "$IMMUADMIN" "$IMMUCLIENT"; do
    if [ ! -x "$cmd" ]; then
        die "Binary not found: $cmd\n  → Run immudb_setup.sh first."
    fi
    ok "Found: $(basename "$cmd")"
done

# Start immudb if not running
section_header "STEP 2 — IMMUDB SERVER"

if pgrep -x immudb >/dev/null 2>&1; then
    ok "immudb is already running"
else
    info "Starting immudb server..."
    nohup "$IMMUD_BIN" \
        --dir "$DATA_DIR" \
        --address 127.0.0.1 \
        --port 3322 \
        --auth=true \
        --maintenance=false \
        >> "$LOG_FILE" 2>&1 &

    info "Waiting for immudb to accept connections..."
    TRIES=0
    while ! "$IMMUCLIENT" status >/dev/null 2>&1; do
        sleep 0.5
        TRIES=$((TRIES + 1))
        [ $TRIES -ge 30 ] && die "immudb did not start after 15s.\nCheck: $LOG_FILE"
    done
    ok "immudb is ready"
fi

# Superadmin login
section_header "STEP 3 — SUPERADMIN LOGIN"

printf "  Log in as the immudb superadmin to create the operator database.\n\n"
hint "Default superadmin username: immudb"
hint "Default superadmin password: immudb"
hint ""
hint "⚠️  Change this password after setup for security!\n"

if ! "$IMMUADMIN" login immudb; then
    die "Superadmin login failed.\n  Ensure immudb is running and credentials are correct."
fi
ok "Superadmin login successful"

# Database creation
section_header "STEP 4 — DATABASE CREATION"

printf "  Create a dedicated database for ORP Engine records.\n"
printf "  This separates ORP data from the default immudb database.\n\n"

hint "Example: BRGY_BUNAO_DB"
hint "Example: BARANGAY_TRUTHCHAIN"
hint "Recommendation: use lowercase letters, digits, and underscores only.\n"

read -r -p "  Enter new database name [BRGY_BUNAO_DB]: " IMMUDB_DB_INPUT
IMMUDB_DB="${IMMUDB_DB_INPUT:-BRGY_BUNAO_DB}"
IMMUDB_DB=$(echo "$IMMUDB_DB" | tr '[:upper:]' '[:lower:]')

if "$IMMUADMIN" database list 2>/dev/null | awk '{print $1}' | grep -qw "^${IMMUDB_DB}$"; then
    warn "Database '${IMMUDB_DB}' already exists — skipping creation."
else
    info "Creating database '${IMMUDB_DB}'..."
    "$IMMUADMIN" database create "$IMMUDB_DB" || die "Database creation failed."
    ok "Database '${IMMUDB_DB}' created"
fi

# User creation
section_header "STEP 5 — OPERATOR USER CREATION"

printf "  Create the operator user that main.py will use to anchor\n"
printf "  document hashes. This user needs 'readwrite' access only.\n"
printf "  immudb prevents modification or deletion of existing records\n"
printf "  at the database level regardless of user role.\n\n"

hint "Example username: ORP_OPERATOR"
hint "Example username: BUNAO_ENGINE"
hint "Recommendation: use lowercase letters, digits, and underscores only.\n"

read -r -p "  Enter operator username [ORP_OPERATOR]: " IMMUDB_USER_INPUT
IMMUDB_USER="${IMMUDB_USER_INPUT:-ORP_OPERATOR}"
IMMUDB_USER=$(echo "$IMMUDB_USER" | tr '[:upper:]' '[:lower:]')

if "$IMMUADMIN" user list 2>/dev/null | awk '{print $1}' | grep -qw "^${IMMUDB_USER}$"; then
    warn "User '${IMMUDB_USER}' already exists — skipping creation."
    hint "To reset password: ~/bin/immuadmin user changepassword ${IMMUDB_USER}\n"
else
    printf "\n"
    info "Creating user '${IMMUDB_USER}' with readwrite access on '${IMMUDB_DB}'..."
    printf "  You will be prompted to set a password for this user.\n"
    printf "  Choose a STRONG password — it will be entered at each engine startup.\n\n"

    "$IMMUADMIN" user create "$IMMUDB_USER" readwrite "$IMMUDB_DB" \
        || die "User creation failed."
    ok "User '${IMMUDB_USER}' created with readwrite access"
fi

# Connection test
section_header "STEP 6 — CONNECTION TEST"

printf "  Verify the operator login works before proceeding.\n"
printf "  Enter the password you set for '${IMMUDB_USER}'.\n\n"

if "$IMMUCLIENT" login "$IMMUDB_USER" --database "$IMMUDB_DB"; then
    "$IMMUCLIENT" set __ORP_HEALTHCHECK__ "ok" > /dev/null 2>&1 || true
    "$IMMUCLIENT" get __ORP_HEALTHCHECK__       > /dev/null 2>&1 || true
    ok "Read/write test passed"
else
    warn "Login verification failed — check the password you entered."
    hint "Retry: ~/bin/immuclient login ${IMMUDB_USER} --database ${IMMUDB_DB}\n"
fi

# Write db_secrets.env
section_header "STEP 7 — WRITING CREDENTIALS FILE"

printf "  Writing username and database name to:\n"
printf "    ~/.identity/db_secrets.env\n\n"

printf "  The operator PASSWORD is NOT stored here.\n"
printf "  It will be prompted interactively when main.py starts\n"
printf "  via Python getpass() and kept in RAM for the session.\n\n"

mkdir -p "$HOME/.identity"
chmod 700 "$HOME/.identity"

SECRETS_FILE="$HOME/.identity/db_secrets.env"

cat > "$SECRETS_FILE" <<EOF
# ─────────────────────────────────────────────────────────────────
# db_secrets.env — ORP immudb OPERATOR CREDENTIALS
# ─────────────────────────────────────────────────────────────────
# Sourced by _orp_core.sh (orp_load_env) at every engine startup.
# Generated by immudb-setup-operator.sh on $(date)
#
# SECURITY NOTES:
#   • This file is chmod 600 (owner read/write only)
#   • Do NOT commit to git — it is outside the repo
#   • The operator PASSWORD is intentionally absent
#   • main.py prompts for password via Python getpass()
#   • Password kept in memory only — never written to disk

IMMUDB_USER="$IMMUDB_USER"
IMMUDB_DB="$IMMUDB_DB"
EOF

chmod 600 "$SECRETS_FILE"
ok "Credentials written to: $SECRETS_FILE (chmod 600)"

# Summary
section_header "SETUP COMPLETE"

printf "  DATABASE:        %s\n" "$IMMUDB_DB"
printf "  IMMUDB_USER:     %s\n" "$IMMUDB_USER"
printf "  SECRETS_FILE:    %s\n\n" "$SECRETS_FILE"

printf "  At engine startup, you will see:\n"
printf "    \"Enter password for vault user [%s]: \"\n\n" "$IMMUDB_USER"

printf "  Enter the password you set during user creation above.\n\n"

ok "immudb operator database setup complete"
