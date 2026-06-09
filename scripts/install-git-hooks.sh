#!/bin/bash
# Install Git hooks for credential protection
# Run this after cloning the repository
# Related: ADR-0031, docs/SECURITY.md

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_SOURCE="$REPO_ROOT/scripts/git-hooks"
HOOKS_TARGET="$REPO_ROOT/.git/hooks"

echo "════════════════════════════════════════════════════════════════"
echo "  Installing Git Hooks for Credential Protection"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if we're in a git repository
if [ ! -d "$REPO_ROOT/.git" ]; then
  echo "❌ ERROR: Not a git repository"
  echo "   Expected .git directory at: $REPO_ROOT/.git"
  exit 1
fi

# Install pre-commit hook
if [ -f "$HOOKS_SOURCE/pre-commit" ]; then
  echo "Installing pre-commit hook..."
  cp "$HOOKS_SOURCE/pre-commit" "$HOOKS_TARGET/pre-commit"
  chmod +x "$HOOKS_TARGET/pre-commit"
  echo "✅ pre-commit hook installed"
else
  echo "⚠️  WARNING: pre-commit hook not found at $HOOKS_SOURCE/pre-commit"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Git Hooks Installation Complete"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Installed hooks:"
ls -lh "$HOOKS_TARGET/pre-commit" 2>/dev/null || echo "  (none)"
echo ""
echo "What this does:"
echo "  - Scans all commits for credential patterns"
echo "  - Blocks commits containing real passwords, tokens, or keys"
echo "  - Allows safe placeholders like <YOUR-CREDENTIAL-HERE>"
echo ""
echo "To test:"
echo "  1. Create a test file with a fake credential"
echo "  2. Try to commit it"
echo "  3. Hook should block the commit"
echo ""
echo "See: docs/SECURITY.md for credential management guidelines"
echo ""
