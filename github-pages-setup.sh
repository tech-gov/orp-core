#!/usr/bin/env bash
# github-pages-setup.sh — Simple GitHub Pages Deploy (no placeholder substitution)
# Copies docs/ content and pushes to origin/main. Expects docs/config.json already present.
# Usage: chmod +x github-pages-setup.sh && ./github-pages-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$SCRIPT_DIR/docs"
RECORDS_DIR="$DOCS_DIR/records"
MANIFEST="$RECORDS_DIR/manifest.json"

echo "Preparing GitHub Pages content..."

# Ensure docs/ exists
mkdir -p "$DOCS_DIR" "$RECORDS_DIR"

# Ensure .nojekyll present
touch "$DOCS_DIR/.nojekyll"

# Ensure manifest.json is valid array
if [ ! -f "$MANIFEST" ]; then
  echo "[]" > "$MANIFEST"
  echo "Created empty manifest.json"
else
  # Basic validation: file must contain a JSON array start
  if ! head -n 1 "$MANIFEST" | grep -q "^\s*\["; then
    echo "Warning: manifest.json not an array — backing up and resetting"
    cp "$MANIFEST" "${MANIFEST}.bak.$(date +%s)"
    echo "[]" > "$MANIFEST"
  fi
fi

# Commit & push docs/
cd "$SCRIPT_DIR"
git add docs/ || true
# Stage .nojekyll explicitly
git add docs/.nojekyll 2>/dev/null || true

if git diff --cached --quiet; then
  echo "No changes to docs/ to commit."
else
  echo "Committing docs/ changes..."
  git commit -m "docs: update public verification portal" --allow-empty || true
fi

# Push if origin remote exists
if git remote get-url origin > /dev/null 2>&1; then
  echo "Pushing docs/ to origin/main..."
  if git push -u origin main; then
    echo "Pushed docs/ to origin/main"
  else
    >&2 echo "Push failed. Ensure SSH key is added to GitHub and remote URL is correct."
  fi
else
  >&2 echo "No git remote 'origin' configured. Skipping push. Run 'git remote add origin <url>' to set one."
fi

echo "GitHub Pages setup finished."
