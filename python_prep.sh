#!/usr/bin/env bash
# python_prep.sh — Python Virtual Environment Setup (IMPROVED)
# ─────────────────────────────────────────────────────────────────
# Creates a Python 3.10+ virtual environment and installs all
# ORP Engine dependencies from requirements.txt.
#
# On WSL2, python3-venv may not be installed. This script checks
# and provides installation instructions if missing.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
REQ_FILE="$SCRIPT_DIR/requirements.txt"

# ── Colours ───────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; GOLD='\033[0;33m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
ok()   { printf "${GREEN}[✔]${NC} %s\n" "$1"; }
info() { printf "${CYAN}[*]${NC} %s\n" "$1"; }
warn() { printf "${GOLD}[!]${NC} %s\n" "$1"; }
die()  { printf "\033[0;31m[✘] ERROR: %s${NC}\n" "$1" >&2; exit 1; }

# ── Banner ────────────────────────────────────────────────────────
clear
printf "${BOLD}${CYAN}"
cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║     ORP ENGINE — Python Virtual Environment Setup       ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}\n"

printf "  Repository: ${BOLD}%s${NC}\n" "$SCRIPT_DIR"
printf "  Venv:       ${BOLD}%s${NC}\n" "$VENV_DIR"
printf "  Requirements: ${BOLD}%s${NC}\n\n" "$REQ_FILE"

# ── Verify Python 3 ──────────────────────────────────────────────
info "Checking Python installation..."

if ! command -v python3 >/dev/null 2>&1; then
    die "python3 not found. Install with: sudo apt-get install python3"
fi

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
printf "  Python version: %s\n\n" "$PYTHON_VERSION"

# ── Verify requirements.txt exists ───────────────────────────────
if [ ! -f "$REQ_FILE" ]; then
    die "requirements.txt not found at $REQ_FILE"
fi
ok "requirements.txt found"

# ── Check if venv module is available ────────────────────────────
info "Checking if venv module is available..."

if ! python3 -m venv --help >/dev/null 2>&1; then
    # Determine Python version for package name
    PYTHON_VERSION_SHORT=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)

    die "python3-venv is not installed.

  On WSL2 Ubuntu, install with:
    sudo apt-get update
    sudo apt-get install -y python${PYTHON_VERSION_SHORT}-venv

  After installation, re-run:
    ./python_prep.sh"
fi
ok "venv module available"

# ── Create or reuse virtual environment ───────────────────────────
if [ -d "$VENV_DIR" ]; then
    warn "Virtual environment already exists at $VENV_DIR"
    warn "Using existing environment. To recreate, run: rm -rf $VENV_DIR"
    printf "\n"
else
    info "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    ok "Virtual environment created"
fi

# ── Activate and upgrade pip ──────────────────────────────────────
printf "\n"
info "Activating virtual environment and upgrading pip..."

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

if ! python3 -m pip install --upgrade pip setuptools wheel >/dev/null 2>&1; then
    die "Failed to upgrade pip. Check your internet connection."
fi
ok "pip, setuptools, wheel upgraded"

# ── Install dependencies ──────────────────────────────────────────
printf "\n"
info "Installing dependencies from requirements.txt..."
printf "  ${DIM}This may take 1–2 minutes depending on your internet speed.${DIM}\n\n"

if ! pip install -r "$REQ_FILE"; then
    die "Failed to install dependencies. Check requirements.txt for syntax errors."
fi
ok "All dependencies installed"

# ── Verify installation ───────────────────────────────────────────
printf "\n"
info "Verifying installed packages..."
pip list

#if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
#    die "Missing critical packages: ${MISSING_PACKAGES[*]}"
#fi

# ── Verify Critical Packages ──────────────────────────────────────
# Note: Pip package names often differ from Python import names.
# Key: "Package-Name:ImportName"
printf "\n"
info "Checking for critical packages..."

CRITICAL_MAP=(
    "Flask:flask"
    "gunicorn:gunicorn"
    "pypdf:pypdf"
    "python-gnupg:gnupg"
    "immudb-py:immudb"
)

printf "\n"
info "Verifying cryptographic and engine modules..."

for entry in "${CRITICAL_MAP[@]}"; do
    pkg="${entry%%:*}"
    mod="${entry#*:}"

    if python3 -c "import $mod" 2>/dev/null; then
        ok "Module '$mod' ($pkg) is functional"
    else
        die "Verification failed: Package '$pkg' installed but module '$mod' cannot be imported."
    fi
done

# ── Summary ───────────────────────────────────────────────────────
printf "\n${BOLD}${CYAN}━━━ Setup Complete ━━━${NC}\n\n"
printf "  ${BOLD}%-25s${NC} %s\n" "Virtualenv:" "$VENV_DIR"
printf "  ${BOLD}%-25s${NC} %s\n" "Python:" "$PYTHON_VERSION"
printf "  ${BOLD}%-25s${NC} $(python3 -m pip --version | awk '{print $2}')\n" "pip:"
printf "\n"
printf "  ${DIM}To activate in the future:${NC}\n"
printf "  ${DIM}  source %s/bin/activate${NC}\n\n" "$VENV_DIR"
printf "  ${DIM}To deactivate:${NC}\n"
printf "  ${DIM}  deactivate${NC}\n\n"
ok "Python environment setup complete."
