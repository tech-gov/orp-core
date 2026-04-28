#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────
# immudb_setup.sh — ORP ENGINE immudb BUILD & INSTALLATION
# ──────────────────────────────────────────────────────────────────
# DESC: Builds immudb from source and installs binaries to $HOME/bin
#       Uses Ubuntu apt for all build dependencies.
#
# USAGE: chmod +x immudb_setup.sh && ./immudb_setup.sh
#
# WHAT IS immudb?
#   Immutable, append-only database at the core of TruthChain.
#   Every document hash is anchored here permanently using
#   Merkle tree cryptographic proof that no record has ever
#   been modified, deleted, or altered.
#
# CREDENTIALS (UPPERCASE):
#   IMMUDB_TAG — Version tag (v1.9.0)
#   IMMUDB_REPO — Git repository URL
#   BIN_DIR — Installation directory ($HOME/bin)
#
# BUILD_TIME: 5–15 minutes depending on hardware
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

BIN_DIR="$HOME/bin"
SRC_DIR="$HOME/immudb-src"
VAULT_DIR="$HOME/.orp_vault"
IMMUDB_REPO="https://github.com/codenotary/immudb.git"
IMMUDB_TAG="v1.9.0"
REQUIRED_GO_MAJOR=1
REQUIRED_GO_MINOR=17

# ──────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────

ok()   { printf "[✔] %s\n" "$1"; }
info() { printf "[*] %s\n" "$1"; }
warn() { printf "[!] %s\n" "$1"; }
die()  { printf "[✘] ERROR: %s\n" "$1" >&2; exit 1; }

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
banner "ORP ENGINE — immudb BUILD & INSTALLATION" \
       "Immutable Append-Only Tamper-Evident Database"

printf "  IMMUDB_TAG:      %s\n" "$IMMUDB_TAG"
printf "  BIN_DIR:         %s\n" "$BIN_DIR"
printf "  SRC_DIR:         %s\n" "$SRC_DIR"
printf "  VAULT_DIR:       %s\n\n" "$VAULT_DIR"

printf "  immudb is an append-only, tamper-evident database that uses\n"
printf "  a Merkle tree to provide cryptographic proof that no historical\n"
printf "  record has ever been modified. Once a hash is written, it cannot\n"
printf "  be deleted or altered — not even by system administrators.\n\n"

mkdir -p "$BIN_DIR" "$VAULT_DIR/data"

# Install build dependencies
section_header "STEP 1 — INSTALLING BUILD DEPENDENCIES"

info "Installing required packages via apt..."
printf "  Required: git, make, golang-go, clang, cmake, netcat-openbsd\n\n"

sudo apt-get update -qq
sudo apt-get install -y \
    git \
    make \
    golang-go \
    clang \
    cmake \
    netcat-openbsd

ok "Build dependencies installed"

# Verify toolchain
section_header "STEP 2 — VERIFYING TOOLCHAIN"

printf "  %-15s %s\n" "git:"    "$(git --version | head -1)"
printf "  %-15s %s\n" "make:"   "$(make --version | head -1)"
printf "  %-15s %s\n" "go:"     "$(go version)"
printf "  %-15s %s\n" "clang:"  "$(clang --version | head -1)"
printf "\n"

# Verify Go version
section_header "STEP 3 — VERIFYING GO VERSION"

info "Verifying Go version (minimum ${REQUIRED_GO_MAJOR}.${REQUIRED_GO_MINOR} required)..."

GO_VERSION_LINE=$(go version)
GO_VERSION=$(echo "$GO_VERSION_LINE" | awk '{print $3}' | sed 's/go//')
GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)

if [ "$GO_MAJOR" -lt "$REQUIRED_GO_MAJOR" ] || \
   ([ "$GO_MAJOR" -eq "$REQUIRED_GO_MAJOR" ] && [ "$GO_MINOR" -lt "$REQUIRED_GO_MINOR" ]); then
    die "Go version too old. Found: $GO_VERSION, Required: ${REQUIRED_GO_MAJOR}.${REQUIRED_GO_MINOR}+\nInstall with: sudo apt-get install golang-go"
fi

ok "Go version check passed: $GO_VERSION"

# Check if already built
section_header "STEP 4 — CHECKING EXISTING BINARIES"

need_build=false
for binary in immudb immuclient immuadmin; do
    if [ ! -x "$BIN_DIR/$binary" ]; then
        need_build=true
        break
    fi
done

if [ "$need_build" = false ]; then
    warn "All binaries already present in $BIN_DIR — skipping build."
    info "Current versions:"
    printf "  immudb:     $("$BIN_DIR/immudb"     version 2>/dev/null | head -1 || echo 'unknown')\n"
    printf "  immuclient: $("$BIN_DIR/immuclient" version 2>/dev/null | head -1 || echo 'unknown')\n"
    printf "  immuadmin:  $("$BIN_DIR/immuadmin"  version 2>/dev/null | head -1 || echo 'unknown')\n"
    printf "\n"
    ok "immudb already installed"
    exit 0
fi

# Clone or update source
section_header "STEP 5 — FETCHING SOURCE CODE"

info "Repository: $IMMUDB_REPO"
info "Tag: $IMMUDB_TAG\n"

if [ -d "$SRC_DIR/.git" ]; then
    info "Updating existing source at $SRC_DIR..."
    git -C "$SRC_DIR" fetch --all --tags --quiet 2>/dev/null || true
    git -C "$SRC_DIR" checkout "$IMMUDB_TAG" --quiet 2>/dev/null \
        || git -C "$SRC_DIR" pull --ff-only --quiet 2>/dev/null || true
    ok "Source updated"
else
    info "Cloning immudb $IMMUDB_TAG..."
    git clone --depth 1 --branch "$IMMUDB_TAG" "$IMMUDB_REPO" "$SRC_DIR" \
        || die "Clone failed. Check your internet connection."
    ok "Source cloned to $SRC_DIR"
fi

# Build
section_header "STEP 6 — BUILDING BINARIES"

info "Building: immudb, immuclient, immuadmin"
printf "  This may take 5–15 minutes depending on your hardware.\n\n"

cd "$SRC_DIR"
if ! make immudb immuclient immuadmin; then
    die "Build failed. Check the output above for errors."
fi

ok "Build complete"

# Install
section_header "STEP 7 — INSTALLING BINARIES"

info "Installing to $BIN_DIR..."
cp -f immudb immuclient immuadmin "$BIN_DIR/"
chmod +x "$BIN_DIR/immudb" "$BIN_DIR/immuclient" "$BIN_DIR/immuadmin"
ok "Binaries installed"

# Update PATH
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    info "Adding $HOME/bin to PATH in ~/.bashrc..."
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/bin:$PATH"
    ok "PATH updated"
fi

# Create vault directory
mkdir -p "$VAULT_DIR/data"
ok "Vault data directory ready: $VAULT_DIR/data"

# Version verification
section_header "STEP 8 — VERSION VERIFICATION"

printf "  %-15s %s\n" "immudb:"     "$("$BIN_DIR/immudb"     version 2>/dev/null | head -1 || echo 'unknown')"
printf "  %-15s %s\n" "immuclient:" "$("$BIN_DIR/immuclient" version 2>/dev/null | head -1 || echo 'unknown')"
printf "  %-15s %s\n" "immuadmin:"  "$("$BIN_DIR/immuadmin"  version 2>/dev/null | head -1 || echo 'unknown')"
printf "\n"

ok "immudb $IMMUDB_TAG installed successfully"
