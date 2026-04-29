#!/usr/bin/env bash
# python_prep.sh — Secure Python Virtual Environment Setup (auto-add pip/setuptools/wheel)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQ_IN="$SCRIPT_DIR/requirements.in"
REQ_FILE="$SCRIPT_DIR/requirements.txt"
CA_CERT="/etc/ssl/certs/ca-certificates.crt"
PIP_LOG="$SCRIPT_DIR/pip-secure.log"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; GOLD='\033[0;33m'
BOLD='\033[1m'; NC='\033[0m'
ok(){ printf "${GREEN}[✔]${NC} %s\n" "$1"; }
info(){ printf "${CYAN}[*]${NC} %s\n" "$1"; }
warn(){ printf "${GOLD}[!]${NC} %s\n" "$1"; }
die(){ printf "\033[0;31m[✘] ERROR: %s${NC}\n" "$1" >&2; exit 1; }

info "Checking Python installation..."
command -v python3 >/dev/null 2>&1 || die "python3 not found. Install python3."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
if [[ "$PYTHON_VERSION" < "3.10" ]]; then
  die "Python 3.10+ required. Found $PYTHON_VERSION"
fi
ok "Python $PYTHON_VERSION available"

[ -f "$REQ_IN" ] || die "requirements.in not found at $REQ_IN. Create it with your top-level pins."

[ -f "$CA_CERT" ] || die "CA certificate bundle not found at $CA_CERT"
ok "CA certificate bundle found"

if ! python3 -m venv --help >/dev/null 2>&1; then
  die "python3-venv not installed. Install with: sudo apt-get install python3-venv"
fi
ok "venv module available"

if [ -d "$VENV_DIR" ]; then
  warn "Virtual environment already exists at $VENV_DIR"
else
  info "Creating virtual environment..."
  python3 -m venv "$VENV_DIR"
  ok "Virtual environment created"
fi

# Activate
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

info "Upgrading pip, setuptools, wheel in venv..."
python3 -m pip install --upgrade pip setuptools wheel >/dev/null
ok "pip, setuptools, wheel upgraded in venv"

info "Installing pip-tools (for pip-compile)..."
python3 -m pip install --upgrade pip-tools >/dev/null
ok "pip-tools installed"

# Ensure pip/setuptools/wheel are pinned in requirements.in
MISSING=()
for PKG in pip setuptools wheel; do
  if ! grep -Eiq "^${PKG}==" "$REQ_IN"; then
    MISSING+=("$PKG")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  info "Auto-adding missing pins for: ${MISSING[*]}"
  # get current versions from the venv
  PIP_VER=$(python3 -m pip --version 2>/dev/null | awk '{print $2}')
  # setuptools and wheel via python import
  read -r SETUPTOOLS_VER WHEEL_VER < <(python3 - <<'PY'
import setuptools, wheel
print(setuptools.__version__, wheel.__version__)
PY
)
  # create a temp file and preserve original comments
  TMP="/tmp/req_in.$$"
  cp "$REQ_IN" "$TMP"
  for PKG in "${MISSING[@]}"; do
    case "$PKG" in
      pip) printf "\n# pinned by python_prep.sh\npip==%s\n" "$PIP_VER" >> "$TMP" ;;
      setuptools) printf "setuptools==%s\n" "$SETUPTOOLS_VER" >> "$TMP" ;;
      wheel) printf "wheel==%s\n" "$WHEEL_VER" >> "$TMP" ;;
    esac
  done
  mv "$TMP" "$REQ_IN"
  ok "Added pins for: ${MISSING[*]} to requirements.in"
else
  ok "pip, setuptools, wheel already pinned in requirements.in"
fi

info "Regenerating hashed requirements.txt from requirements.in..."
# Always call the pip-compile binary inside the venv, not the module
"$VENV_DIR/bin/pip-compile" --generate-hashes "$REQ_IN" --output-file "$REQ_FILE"

# Verify file exists and is non-empty
if [ ! -s "$REQ_FILE" ]; then
  die "requirements.txt was not created at $REQ_FILE. Check pip-compile output."
fi
ok "requirements.txt regenerated with hashes at $REQ_FILE"

python3 -m piptools.scripts.compile --generate-hashes --output-file "$REQ_FILE" "$REQ_IN"
ok "requirements.txt regenerated with hashes"

info "Installing dependencies with strict security flags..."
pip install \
  --require-virtualenv \
  --isolated \
  --no-cache-dir \
  --require-hashes \
  -r "$REQ_FILE" \
  --cert "$CA_CERT" \
  --retries 3 \
  --timeout 10 \
  --no-input \
  --log "$PIP_LOG"

ok "Dependencies installed securely"

info "Running pip-audit..."
if ! python3 -m pip_audit.cli >/dev/null 2>&1; then
  warn "pip-audit found issues. Run 'pip-audit' locally to inspect."
else
  ok "pip-audit passed (no known vulnerabilities found)"
fi

info "Saving environment snapshot to requirements.lock..."
python3 -m pip freeze > "$SCRIPT_DIR/requirements.lock"
ok "requirements.lock written"

printf "\n${BOLD:-}${CYAN:-}━━━ Setup Complete ━━━${NC:-}\n"
