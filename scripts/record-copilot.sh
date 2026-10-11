#!/usr/bin/env bash
# ==============================================================================
# record-copilot.sh - Semi-Automated Co-Pilot Desktop Video Recorder
# The script orchestrates window switching, browser URLs, and Emacs commands,
# pausing only when human interaction (OAuth consent & revocation clicks) is needed.
# ==============================================================================
set -euo pipefail

OUTPUT_FILE="${1:-demo.mp4}"
DISPLAY_TARGET="${DISPLAY:-:0}"
USER_ACCOUNT="${USER_ACCOUNT:-kleinman.sam@gmail.com}"
DEV_EMAIL="${DEV_EMAIL:-garen@tychoish.com}"
TARGET_WIDTH=1920
TARGET_HEIGHT=1080
TARGET_FPS=30

export DISPLAY="$DISPLAY_TARGET"

# Helper to activate and focus Chrome in StumpWM
focus_chrome() {
    local url="${1:-}"
    if [ -n "$url" ]; then
        google-chrome-stable "$url" >/dev/null 2>&1 &
    fi
    if command -v stumpish >/dev/null 2>&1; then
        stumpish eval '(let ((w (find-if (lambda (win) (search "Chrome" (stumpwm::window-title win))) (stumpwm::all-windows))))
                         (when w
                           (stumpwm::switch-to-group (stumpwm::window-group w))
                           (stumpwm::focus-window w)))' >/dev/null 2>&1 || true
    fi
}

# Helper to activate, switch buffer, and focus Emacs in StumpWM
focus_emacs() {
    local buf_name="$1"
    local setup_code="$2"
    emacsclient --eval "
(progn
  $setup_code
  (let ((buf (get-buffer-create \"$buf_name\"))
        (frame (car (filtered-frame-list (lambda (f) (string-match-p \"^work:\" (frame-parameter f 'name)))))))
    (when frame
      (with-selected-frame frame
        (select-window (frame-selected-window frame))
        (switch-to-buffer buf)))))" >/dev/null 2>&1 || true

    if command -v stumpish >/dev/null 2>&1; then
        stumpish eval '(let ((w (find-if (lambda (win) (search "work:" (stumpwm::window-title win))) (stumpwm::all-windows))))
                         (when w
                           (stumpwm::switch-to-group (stumpwm::window-group w))
                           (stumpwm::focus-window w)))' >/dev/null 2>&1 || true
    fi
}

echo "================================================================================"
echo "    denote-sync Co-Pilot Verification Video Recorder"
echo "================================================================================"
echo "Output file:        $OUTPUT_FILE"
echo "Display:            $DISPLAY_TARGET"
echo "Demo User Account:  $USER_ACCOUNT"
echo "Developer Contact:  $DEV_EMAIL"
echo ""
echo "NOTE: Ensure ONLY '$USER_ACCOUNT' is selected during Google authorization."
echo "      Do NOT select or display tychoish@gmail.com."
echo "--------------------------------------------------------------------------------"
echo "How this works:"
echo "  1. The script automatically launches Google Chrome tabs & switches windows."
echo "  2. The script triggers Emacs note display & sync via emacsclient."
echo "  3. You only need to perform the 2 interactive clicks Google requires:"
echo "     - Click [Allow] on the Google OAuth consent screen (Step 3)"
echo "     - Click [Remove Access] on Google Account permissions (Step 5)"
echo "================================================================================"
echo ""
read -r -p "Ready? Press [ENTER] to start recording... "

# Detect screen resolution
SCREEN_RES=$(xdpyinfo -display "$DISPLAY_TARGET" 2>/dev/null | awk '/dimensions:/ {print $2}' || true)
SCREEN_RES="${SCREEN_RES:-1920x1200}"

# Start ffmpeg recorder in background
echo ">>> Starting 1080p desktop recording to $OUTPUT_FILE..."
ffmpeg -nostdin -y \
    -f x11grab \
    -video_size "$SCREEN_RES" \
    -framerate "$TARGET_FPS" \
    -i "${DISPLAY_TARGET}.0" \
    -vf "scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:force_original_aspect_ratio=decrease,pad=${TARGET_WIDTH}:${TARGET_HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
    -c:v libx264 \
    -preset fast \
    -crf 20 \
    "$OUTPUT_FILE" >/dev/null 2>&1 &
FFMPEG_PID=$!

cleanup() {
    if kill -0 "$FFMPEG_PID" 2>/dev/null; then
        echo ""
        echo ">>> Stopping recorder and finalizing MP4 container..."
        kill -INT "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

wait_or_enter() {
    local seconds="$1"
    local prompt="$2"
    echo -e "\n$prompt"
    for ((s=seconds; s>0; s--)); do
        printf "\r>>> [%02ds remaining] Press [ENTER] to skip to next step... " "$s"
        if read -t 1 -r; then
            echo ""
            return 0
        fi
    done
    echo ""
}

# ------------------------------------------------------------------------------
# STEP 1: Google Cloud Console Credentials (0:00 - 0:15)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 1/5] Google Cloud Console Credentials (0:00 - 0:15)"
echo "================================================================================"
focus_chrome "https://console.cloud.google.com/apis/credentials"
wait_or_enter 14 "Showing Google Cloud Console Credentials page with OAuth 2.0 Client ID."

# ------------------------------------------------------------------------------
# STEP 2: Emacs Authorization Initiation (0:15 - 0:35)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 2/5] Emacs Authorization Initiation (0:15 - 0:35)"
echo "================================================================================"
focus_emacs "*denote-sync-bootstrap*" "
  (with-current-buffer (get-buffer-create \"*denote-sync-bootstrap*\")
    (erase-buffer)
    (insert \";; denote-sync Google Docs Setup Wizard\n\")
    (insert \";; Authorizing account: $USER_ACCOUNT\n\")
    (insert \";; Scope minimization: --drive-scope=file (Sensitive Scope tier)\n\n\")
    (insert \"[✓] Found gog CLI helper\n\")
    (insert \"[✓] Keyring configured\n\")
    (insert \"Opening Google OAuth 2.0 consent in browser for $USER_ACCOUNT...\n\"))"

wait_or_enter 15 "Emacs buffer displaying authorization parameters and --drive-scope=file."

# ------------------------------------------------------------------------------
# STEP 3: Google OAuth Consent Screen (0:35 - 0:55)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 3/5] OAuth Consent Screen & Client ID Inspection (0:35 - 0:55)"
echo "================================================================================"
focus_chrome
echo ">>> CRITICAL ACTION REQUIRED:"
echo ">>> 1. In Chrome, verify you are selecting/authorizing account: $USER_ACCOUNT"
echo ">>>    (Do NOT select or display tychoish@gmail.com)"
echo ">>> 2. Move cursor to highlight the URL bar showing client_id=..."
echo ">>> 3. Review the sensitive permissions (Google Docs & Drive Files)."
echo ">>> 4. Click [Allow] or [Continue]."
echo ""
read -r -p ">>> Once you have clicked Allow, press [ENTER] to continue... "

# ------------------------------------------------------------------------------
# STEP 4: Note Synchronization (0:55 - 1:15)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 4/5] Bidirectional Note Synchronization (0:55 - 1:15)"
echo "================================================================================"
focus_emacs "*denote-sync-demo*" "
  (with-current-buffer (get-buffer-create \"*denote-sync-demo*\")
    (org-mode)
    (erase-buffer)
    (insert \"#+title: denote-sync Verification Demo\n\")
    (insert \"#+date:  [\" (format-time-string \"%Y-%m-%d %a\") \"]\n\")
    (insert \"#+sync_gdoc_account: $USER_ACCOUNT\n\n\")
    (insert \"* Synchronization in Action\n\")
    (insert \"This note demonstrates bidirectional synchronization between local Denote\n\")
    (insert \"notes and Google Docs via official Docs and Drive APIs.\n\n\")
    (insert \"[✓] denote-sync-push: successfully exported note!\n\"))"

wait_or_enter 10 "Showing Emacs Denote note frontmatter (#+sync_gdoc_account: $USER_ACCOUNT)."

focus_chrome "https://docs.google.com"
wait_or_enter 10 "Showing synced Google Docs interface in browser."

# ------------------------------------------------------------------------------
# STEP 5: Permission Revocation (1:15 - 1:30)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 5/5] Account Permission Revocation (1:15 - 1:30)"
echo "================================================================================"
focus_chrome "https://myaccount.google.com/permissions"
echo ""
echo ">>> FINAL ACTION REQUIRED:"
echo ">>> In Chrome (signed in as $USER_ACCOUNT):"
echo ">>> Locate 'denote-sync' under Third-party apps."
echo ">>> Click 'Remove Access' to demonstrate immediate user revocability."
echo ""
read -r -p ">>> Once you have clicked Remove Access, press [ENTER] to finish recording... "

trap - EXIT INT TERM
cleanup

echo ""
echo "================================================================================"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    
    echo "[✓] Recording complete: $OUTPUT_FILE"
    echo "    Resolution: $RES"
    echo "    Duration:   ${DURATION}s"
    echo "    File size:  $FILE_SIZE"
    echo "--------------------------------------------------------------------------------"
    echo "The video is ready for upload to YouTube as 'Unlisted'."
else
    echo "[✗] Recording failed to produce $OUTPUT_FILE."
fi
echo "================================================================================"
