#!/usr/bin/env bash
# orp-env-bootstrap.sh — ORP Engine Environment Configuration
# ─────────────────────────────────────────────────────────────────
# Creates the .env file with all LGU-specific configuration.
# Run once on first setup. To reconfigure, delete .env and re-run.
#
# No credentials are hardcoded — all values are entered interactively.
# The immudb password is NOT stored here; it is prompted at runtime.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# ── Colours ───────────────────────────────────────────────────────
CYAN='\033[0;36m'; GOLD='\033[0;33m'; GREEN='\033[0;32m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

section() { printf "\n${BOLD}${CYAN}━━━ %s ━━━${NC}\n\n" "$1"; }
hint()    { printf "  ${DIM}%s${NC}\n" "$1"; }
ok()      { printf "${GREEN}[✔]${NC} %s\n" "$1"; }

# ── Banner ────────────────────────────────────────────────────────
clear
printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║      ORP ENGINE — ENVIRONMENT CONFIGURATION              ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"
printf "  This script creates the ${BOLD}.env${NC} configuration file for your\n"
printf "  barangay deployment. All values are specific to your LGU —\n"
printf "  nothing here applies to any other deployment.\n\n"
printf "  ${DIM}No passwords are stored in .env. The immudb password is\n"
printf "  prompted at engine startup and kept in RAM only.${NC}\n\n"

if [ -f "$ENV_FILE" ]; then
    printf "${GOLD}[!]${NC} .env already exists at: %s\n" "$ENV_FILE"
    printf "    Delete it and re-run to reconfigure.\n"
    exit 0
fi

# ── Prompt helper ─────────────────────────────────────────────────
ask() {
    local var="$1" msg="$2" default="$3"
    local val
    printf "  ${BOLD}%s${NC}\n" "$msg"
    if [ -n "$default" ]; then
        printf "  ${DIM}Default: %s${NC}\n" "$default"
    fi
    read -rp "  → " val
    val="${val:-$default}"
    printf -v "$var" '%s' "$val"
    printf "\n"
}

# ── Section 1: LGU Identity ───────────────────────────────────────
section "LGU Identity"

printf "  These values appear on every stamped document and audit record.\n"
printf "  Use the official name exactly as it appears on legal documents.\n\n"

hint "Example: Barangay Buñao, City of Dumaguete, Negros Oriental"
ask LGU_NAME "LGU / Barangay Name (official, full name)" ""
while [ -z "$LGU_NAME" ]; do
    printf "  ${GOLD}[!]${NC} LGU Name cannot be empty.\n\n"
    ask LGU_NAME "LGU / Barangay Name (official, full name)" ""
done

hint "Example: HON. JUAN DELA CRUZ"
hint "Include the honorific (HON., ATTY., DR., etc.)"
ask LGU_SIGNER_NAME "Authorized Signatory — full name with title" ""
while [ -z "$LGU_SIGNER_NAME" ]; do
    printf "  ${GOLD}[!]${NC} Signer name cannot be empty.\n\n"
    ask LGU_SIGNER_NAME "Authorized Signatory — full name with title" ""
done

hint "Example: Punong Barangay"
ask LGU_SIGNER_POSITION "Signatory's official position / title" "Punong Barangay"

# ── Section 2: Operator ───────────────────────────────────────────
section "Operator Configuration"

printf "  The operator email is used as the identity for ephemeral GPG keys.\n"
printf "  It must be consistent to maintain your cryptographic identity.\n\n"

hint "Example: operator@bgy-bunao.gov.ph"
ask OPERATOR_GPG_EMAIL "Operator GPG email" ""
while [[ "$OPERATOR_GPG_EMAIL" != *"@"* ]]; do
    printf "  ${GOLD}[!]${NC} Must contain '@'. Enter a valid identity email.\n\n"
    ask OPERATOR_GPG_EMAIL "Operator GPG email" ""
done

# ── Section 3: GitHub Ledger Integration ──────────────────────────
section "GitHub Public Ledger"

printf "  To enable public verification, the engine publishes documents\n"
printf "  to a GitHub Pages ledger. Citizens can scan the QR code on any\n"
printf "  stamped document to reach this URL and verify it.\n\n"

hint "Example username/org: openrespublica"
read -rp "  GitHub Username or Organization: " GITHUB_OWNER
GITHUB_OWNER="${GITHUB_OWNER:-}"

hint "Example repo: brgy-bunao-ledger"
read -rp "  GitHub Portal Repository Name [truthchain-ledger]: " GITHUB_PAGES_REPO
GITHUB_PAGES_REPO="${GITHUB_PAGES_REPO:-truthchain-ledger}"

if [ -n "$GITHUB_OWNER" ]; then
    GITHUB_PORTAL_URL="https://${GITHUB_OWNER}.github.io/${GITHUB_PAGES_REPO}/verify.html"
else
    # Fallback to default if no owner is provided
    GITHUB_PORTAL_URL="https://openrespublica.github.io/verify.html"
fi

ok "Public Ledger URL set to: $GITHUB_PORTAL_URL"

# ── Section 4: System paths (auto-derived) ───────────────────────
section "System Configuration (Auto-configured)"

FLASK_PORT=5000
IMMUDB_HOST="127.0.0.1:3322"
IMMUDB_USER="orp_operator"
IMMUDB_DB="brgy_bunaodb"
GITHUB_REPO_PATH="$SCRIPT_DIR"
PKI_DIR="$HOME/.orp_engine/ssl"

printf "  ${BOLD}%-25s${NC} %s\n" "Flask port:"        "$FLASK_PORT"
printf "  ${BOLD}%-25s${NC} %s\n" "immudb host:port:" "$IMMUDB_HOST"
printf "  ${BOLD}%-25s${NC} %s\n" "PKI directory:"    "$PKI_DIR"
printf "\n"

# ── Write .env ────────────────────────────────────────────────────
section "Writing Configuration"

cat > "$ENV_FILE" <<EOF
# .env — ORP Engine Configuration
# Generated: $(date)
# Deployment: $LGU_NAME

# ── LGU Identity ──────────────────────────────────────────────────
LGU_NAME="$LGU_NAME"
LGU_SIGNER_NAME="$LGU_SIGNER_NAME"
LGU_SIGNER_POSITION="$LGU_SIGNER_POSITION"
LGU_TIMEZONE="Asia/Manila"

# ── Operator Identity ─────────────────────────────────────────────
OPERATOR_GPG_EMAIL="$OPERATOR_GPG_EMAIL"

# ── Repository & Public Ledger ────────────────────────────────────
GITHUB_REPO_PATH="$GITHUB_REPO_PATH"
GITHUB_OWNER="$GITHUB_OWNER"
GITHUB_PAGES_REPO="$GITHUB_PAGES_REPO"
GITHUB_PORTAL_URL="$GITHUB_PORTAL_URL"

# ── PKI Directory ─────────────────────────────────────────────────
PKI_DIR="$PKI_DIR"

# ── Flask / Gunicorn ──────────────────────────────────────────────
FLASK_PORT=$FLASK_PORT

# ── immudb ────────────────────────────────────────────────────────
IMMUDB_HOST="$IMMUDB_HOST"
IMMUDB_USER="$IMMUDB_USER"
IMMUDB_DB="$IMMUDB_DB"
EOF

chmod 600 "$ENV_FILE"

ok ".env written to: $ENV_FILE"
ok "Permissions set to 600 (owner read/write only)."

printf "\n${BOLD}${CYAN}━━━ Configuration Summary ━━━${NC}\n\n"
printf "  ${BOLD}%-30s${NC} %s\n" "LGU Name:"             "$LGU_NAME"
printf "  ${BOLD}%-30s${NC} %s\n" "Authorized Signatory:" "$LGU_SIGNER_NAME"
printf "  ${BOLD}%-30s${NC} %s\n" "Public Ledger URL:"    "$GITHUB_PORTAL_URL"
printf "\n"
printf "  ${DIM}To change any value: delete .env and re-run this script.${NC}\n\n"
