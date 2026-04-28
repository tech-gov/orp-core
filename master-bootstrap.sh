#!/usr/bin/env bash
# master-bootstrap.sh — ORP Engine Master Setup Orchestrator
# Installs system dependencies, runs idempotent setup steps,
# and deploys the portal to GitHub Pages.
# Usage: chmod +x master-bootstrap.sh && ./master-bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-$HOME/orp-setup.log}"
ENV_FILE="$SCRIPT_DIR/.env"

# ──────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────

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

ok()   { printf "[✔] %s\n" "$1" | tee -a "$LOG_FILE"; }
info() { printf "[*] %s\n" "$1" | tee -a "$LOG_FILE"; }
warn() { printf "[!] %s\n" "$1" | tee -a "$LOG_FILE"; }
die()  { printf "[✘] ERROR: %s\n" "$1" >&2 | tee -a "$LOG_FILE"; exit 1; }
log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

# ──────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────

REQUIRED_SCRIPTS=(
  "orp-timezone-setup.sh"
  "orp-env-bootstrap.sh"
  "python_prep.sh"
  "immudb_setup.sh"
  "immudb-setup-operator.sh"
  "orp-pki-setup.sh"
  "nginx-setup.sh"
  "repo-init.sh"
)

REQUIRED_PKGS=(git jq curl python3 python3-pip python3-venv shellcheck)

# ──────────────────────────────────────────────────────────────────
# MAIN BOOTSTRAP
# ──────────────────────────────────────────────────────────────────

clear
banner "OPENRESPUBLICA — ORP ENGINE MASTER BOOTSTRAP" \
       "TruthChain Sovereign Document Issuance System"

log "Bootstrap started at $(date)"
log "SCRIPT_DIR: $SCRIPT_DIR"

# Preflight: install OS packages on Debian/Ubuntu
section_header "STEP 0/9 — Checking System Dependencies"
MISSING=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  info "Missing system packages: ${MISSING[*]}"
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
      info "Installing packages via apt (you may be prompted for sudo)..."
      sudo apt-get update
      sudo apt-get install -y "${MISSING[@]}"
      ok "Installed system dependencies."
    else
      die "Automatic system package installation only supported on Debian/Ubuntu. Please install: ${MISSING[*]}"
    fi
  else
    die "Cannot detect OS. Please install: ${MISSING[*]}"
  fi
else
  ok "All required system packages are present."
fi

# Verify required scripts exist
info "Verifying setup scripts..."
for script in "${REQUIRED_SCRIPTS[@]}"; do
  [ -f "$SCRIPT_DIR/$script" ] || die "Missing script: $script"
done
ok "All required scripts found."

printf "\n"
warn "This script will install packages and configure services."
read -rp "Press ENTER to begin, or Ctrl+C to abort... "

# ──────────────────────────────────────────────────────────────────
# STEP RUNNER
# ──────────────────────────────────────────────────────────────────

run_step() {
  local step_num="$1"
  local step_desc="$2"
  local script_name="$3"
  local skip_if="${4:-}"

  section_header "STEP $step_num — $step_desc"

  if [ -n "$skip_if" ] && [ -e "$skip_if" ]; then
    warn "Already complete — skipping. Remove '$skip_if' to redo."
    log "SKIP: $step_desc"
    return 0
  fi

  log "START: $step_desc"
  bash "$SCRIPT_DIR/$script_name" 2>&1 | sed 's/^/    /' | tee -a "$LOG_FILE"
  local exit_code=${PIPESTATUS[0]}
  if [ $exit_code -ne 0 ]; then
    die "Script failed (exit $exit_code): $script_name"
  fi
  log "DONE: $step_desc"
  ok "${step_desc} complete."
}

# ──────────────────────────────────────────────────────────────────
# EXECUTION
# ──────────────────────────────────────────────────────────────────

run_step "1/9" "Timezone (Asia/Manila)" "orp-timezone-setup.sh"
run_step "2/9" "Environment Configuration (.env & docs/config.json)" "orp-env-bootstrap.sh" "$ENV_FILE"
run_step "3/9" "Python Virtualenv + Dependencies" "python_prep.sh" "$SCRIPT_DIR/.venv"
run_step "4/9" "immudb Binary Build" "immudb_setup.sh" "$HOME/bin/immudb"
run_step "5/9" "immudb Operator Database + Secrets" "immudb-setup-operator.sh" "$HOME/.identity/db_secrets.env"

PKI_DIR_DEFAULT="$HOME/.orp_engine/ssl"
if [ -f "$ENV_FILE" ]; then set -a; source "$ENV_FILE"; set +a; fi
run_step "6/9" "Sovereign PKI (mTLS Certificates)" "orp-pki-setup.sh" "${PKI_DIR:-$PKI_DIR_DEFAULT}/sovereign_root.crt"

run_step "7/9" "Nginx mTLS Gateway" "nginx-setup.sh"
run_step "8/9" "Repository Directory Structure" "repo-init.sh" "$SCRIPT_DIR/docs/records/manifest.json"

# Always sync GitHub Pages at the end
section_header "STEP 9/9 — Build & Deploy Public Portal"
if [ -f "$SCRIPT_DIR/github-pages-setup.sh" ]; then
  bash "$SCRIPT_DIR/github-pages-setup.sh"
else
  warn "github-pages-setup.sh missing — skipping portal deployment."
fi

# ──────────────────────────────────────────────────────────────────
# COMPLETION SUMMARY
# ──────────────────────────────────────────────────────────────────

clear
banner "OPENRESPUBLICA — SETUP COMPLETE" \
       "ORP Engine Environment Ready for Operation"

ok "ORP Engine environment is ready."
PKI_FINAL="${PKI_DIR:-$PKI_DIR_DEFAULT}"

printf "\n  NEXT STEPS:\n\n"
printf "  1. Install operator certificate in your browser:\n\n"
printf "       Chrome/Edge: Settings → Privacy → Manage certificates → Import\n"
printf "       Select: %s/OPERATOR_01.P12\n\n" "$PKI_FINAL"
printf "  2. Launch the engine:\n\n"
printf "       ./run_orp.sh\n\n"
printf "  3. When prompted, paste the session SSH key to GitHub:\n\n"
printf "       GitHub → Settings → SSH Keys → New SSH Key\n\n"
printf "  4. Open the portal in your browser:\n\n"
printf "       https://localhost:9443\n\n"
printf "  Setup log: %s\n\n" "$LOG_FILE"

log "Bootstrap complete at $(date)"
