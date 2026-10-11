#!/usr/bin/env bash
# ==============================================================================
# setup-gdocs.sh - Interactive setup script for denote-sync Google Docs integration
# ==============================================================================
set -euo pipefail

echo "=== denote-sync Google Docs Setup ==="
echo

# 1. Check for gog CLI
if ! command -v gog >/dev/null 2>&1; then
    echo "Error: 'gog' CLI is not found in PATH."
    echo "Install via:"
    echo "  go install github.com/openclaw/gogcli/cmd/gog@latest"
    echo "  sudo ln -sf ~/go/bin/gog /usr/local/bin/gog"
    exit 1
fi
echo "[✓] Found gog: $(command -v gog) ($(gog version 2>/dev/null || echo 'installed'))"

# 2. Configure credentials
echo
echo "--- Step 1: OAuth Client Credentials ---"
read -rp "Do you have a Google OAuth Client JSON credentials file? [y/N]: " has_json
if [[ "$has_json" =~ ^[Yy]$ ]]; then
    read -rp "Enter path to credentials JSON: " creds_path
    if [[ ! -f "$creds_path" ]]; then
        echo "Error: File not found: $creds_path" >&2
        exit 1
    fi
    gog auth credentials set "$creds_path" --insecure
    echo "[✓] Client credentials registered."
else
    echo "Skipping client credentials upload (using existing or system defaults)."
fi

# 3. Configure file keyring backend
echo
echo "--- Step 2: Encrypted Keyring Backend ---"
gog auth keyring file
echo "[✓] Configured file keyring at ~/.local/share/gogcli/keyring"

# 4. Keyring passphrase
echo
echo "--- Step 3: Keyring Passphrase ---"
if [[ -z "${GOG_KEYRING_PASSWORD:-}" ]]; then
    read -rsp "Enter a secure passphrase for the file keyring: " GOG_KEYRING_PASSWORD
    echo
    if [[ -z "$GOG_KEYRING_PASSWORD" ]]; then
        echo "Error: Passphrase cannot be empty." >&2
        exit 1
    fi
fi
export GOG_KEYRING_PASSWORD

# 5. Authorize Google account
echo
echo "--- Step 4: Authorize Google Account ---"
echo "We will now authenticate your account with minimal sensitive scope:"
echo "  --services=docs,drive --drive-scope=file"
echo
read -rp "Enter your Google email address: " user_email
if [[ -z "$user_email" ]]; then
    echo "Error: Email cannot be empty." >&2
    exit 1
fi

gog auth add "$user_email" --services=docs,drive --drive-scope=file
echo "[✓] Account authorized."

# 6. Run diagnostic check
echo
echo "--- Step 5: Verification & Diagnostics ---"
gog auth doctor

# 7. Print Emacs user configuration
echo
echo "======================================================================"
echo "Setup Successful!"
echo "Add the following snippet to your user configuration"
echo "(e.g., ~/.emacs.d/user/personal.el):"
echo "======================================================================"
echo
cat <<EOF
(setenv "GOG_KEYRING_PASSWORD" "$GOG_KEYRING_PASSWORD")
(setq denote-sync-gdocs-default-account "$user_email")
(setq denote-sync-gdocs-drive-scope "file")
(add-to-list 'denote-sync-parent-registry
             '("Google Docs" . (google-docs . ("$user_email" . nil))))
EOF
echo
echo "======================================================================"
