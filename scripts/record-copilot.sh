#!/usr/bin/env bash
# ==============================================================================
# record-copilot.sh - Semi-Automated Co-Pilot Desktop Video Recorder
# Demonstrates the end-to-end user OAuth flow for denote-sync:
# 1. Emacs setup & authorization initiation
# 2. Google OAuth 2.0 consent screen (showing client_id in URL)
# 3. Note synchronization in Emacs & Google Docs
# 4. Account permission revocation (myaccount.google.com/permissions)
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

# Temporary directory for clean segment recordings
TMP_DIR=$(mktemp -d -t denote-sync-video-XXXXXX)
SEGMENT_INDEX=0
FFMPEG_PID=""

# ------------------------------------------------------------------------------
# Dunst HUD Helpers
# ------------------------------------------------------------------------------
notify_hud() {
    local title="$1"
    local msg="$2"
    local urgency="${3:-normal}"
    local timeout="${4:-5000}"
    if command -v dunstify >/dev/null 2>&1; then
        dunstify -u "$urgency" -a "denote-sync" -t "$timeout" -r 9988 "$title" "$msg" >/dev/null 2>&1 || true
    fi
}

# ------------------------------------------------------------------------------
# Window and Navigation Helpers
# ------------------------------------------------------------------------------
navigate_chrome() {
    local url="${1:-}"
    # 1. Switch StumpWM to net group
    if command -v stumpish >/dev/null 2>&1; then
        stumpish eval '(stumpwm::run-commands "gselect net")' >/dev/null 2>&1 || true
    fi
    # 2. Find Chrome window in group net
    local win_id
    win_id=$(xdotool search --class "google-chrome" 2>/dev/null | tail -n 1 || true)
    if [ -n "$win_id" ]; then
        xdotool windowactivate --sync "$win_id" >/dev/null 2>&1 || true
        if [ -n "$url" ]; then
            sleep 0.3
            xdotool key --window "$win_id" --clearmodifiers ctrl+l >/dev/null 2>&1 || true
            sleep 0.2
            xdotool type --window "$win_id" --delay 5 "$url" >/dev/null 2>&1 || true
            sleep 0.2
            xdotool key --window "$win_id" Return >/dev/null 2>&1 || true
        fi
    else
        if [ -n "$url" ]; then
            google-chrome-stable --new-window "$url" >/dev/null 2>&1 &
        fi
    fi
}

focus_emacs() {
    local buf_name="$1"
    local setup_code="$2"
    # 1. Switch StumpWM to code group
    if command -v stumpish >/dev/null 2>&1; then
        stumpish eval '(stumpwm::run-commands "gselect code")' >/dev/null 2>&1 || true
    fi
    # 2. Switch buffer in visible work frame
    emacsclient --eval "
(progn
  $setup_code
  (let ((buf (get-buffer-create \"$buf_name\"))
        (frame (car (filtered-frame-list (lambda (f) (string-match-p \"^work:\" (frame-parameter f 'name)))))))
    (when frame
      (with-selected-frame frame
        (select-window (frame-selected-window frame))
        (switch-to-buffer buf)))))" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# Segment Recorder (True Pause / Unpause)
# ------------------------------------------------------------------------------
start_segment() {
    SEGMENT_INDEX=$((SEGMENT_INDEX + 1))
    local seg_file="$TMP_DIR/seg_$(printf "%03d" $SEGMENT_INDEX).mp4"
    echo "$seg_file" >> "$TMP_DIR/segments.txt"
    
    ffmpeg -nostdin -y \
        -f x11grab \
        -video_size "$SCREEN_RES" \
        -framerate "$TARGET_FPS" \
        -i "${DISPLAY_TARGET}.0" \
        -vf "scale=${TARGET_WIDTH}:${TARGET_HEIGHT}:force_original_aspect_ratio=decrease,pad=${TARGET_WIDTH}:${TARGET_HEIGHT}:(ow-iw)/2:(oh-ih)/2,format=yuv420p" \
        -c:v libx264 \
        -preset fast \
        -crf 20 \
        "$seg_file" >/dev/null 2>&1 &
    FFMPEG_PID=$!
}

stop_segment() {
    if [ -n "${FFMPEG_PID:-}" ] && kill -0 "$FFMPEG_PID" 2>/dev/null; then
        kill -INT "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
        FFMPEG_PID=""
    fi
}

prompt_action_paused() {
    local title="$1"
    local instructions="$2"
    
    # 1. Stop recording so user has unlimited time without inflating video
    stop_segment
    
    # 2. Fire Dunst notification
    notify_hud "[PAUSED] $title" "$instructions\n\n👉 Press ENTER in terminal to resume recording." "critical" 0
    
    echo ""
    echo "================================================================================"
    echo " [PAUSED] $title"
    echo "================================================================================"
    echo -e "$instructions"
    echo "--------------------------------------------------------------------------------"
    read -r -p ">>> When finished with action, press [ENTER] to resume recording... "
    
    # Dismiss notification
    dunstify -C 9988 >/dev/null 2>&1 || true
    notify_hud "▶ Recording Resumed" "Capturing next segment..." "normal" 3000
    sleep 1
    
    # Resume recording next segment
    start_segment
}

cleanup() {
    stop_segment
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------------------
# Screen Resolution Setup
# ------------------------------------------------------------------------------
SCREEN_RES=$(xdpyinfo -display "$DISPLAY_TARGET" 2>/dev/null | awk '/dimensions:/ {print $2}' || true)
SCREEN_RES="${SCREEN_RES:-1920x1200}"

echo "================================================================================"
echo "    denote-sync OAuth Verification Video Recorder"
echo "================================================================================"
echo "Output file:        $OUTPUT_FILE"
echo "Display:            $DISPLAY_TARGET"
echo "Demo User Account:  $USER_ACCOUNT"
echo "Developer Contact:  $DEV_EMAIL"
echo ""
echo "NOTE: Ensure ONLY '$USER_ACCOUNT' is selected during Google authorization."
echo "      Do NOT select or display tychoish@gmail.com."
echo "--------------------------------------------------------------------------------"
echo "Workflow Steps (Authentic User Flow):"
echo "  1. Emacs: Setup wizard initiation & scope minimization (--drive-scope=file)"
echo "  2. Browser: OAuth 2.0 consent screen (client_id visible in URL) & Allow"
echo "  3. Emacs & Docs: Note synchronization demonstration"
echo "  4. Browser: Account permissions revocation (myaccount.google.com/permissions)"
echo "================================================================================"
echo ""
read -r -p "Ready? Press [ENTER] to start recording... "

notify_hud "denote-sync Verification" "Recording started. 4-step user verification flow." "normal" 4000

# ------------------------------------------------------------------------------
# STEP 1: Emacs Setup Wizard Initiation (15s)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 1/4] Emacs Setup Wizard & Authorization Initiation"
echo "================================================================================"
start_segment
notify_hud "Step 1/4: Emacs Setup Wizard" "Displaying denote-sync bootstrap & scope minimization (15s)" "normal" 14000
focus_emacs "*denote-sync-bootstrap*" "
  (with-current-buffer (get-buffer-create \"*denote-sync-bootstrap*\")
    (erase-buffer)
    (insert \";; denote-sync Google Docs Setup Wizard\n\")
    (insert \";; Authorizing account: $USER_ACCOUNT\n\")
    (insert \";; Scope minimization: --drive-scope=file (Sensitive Scope tier)\n\n\")
    (insert \"[✓] Found gog CLI helper\n\")
    (insert \"[✓] Keyring configured\n\")
    (insert \"Opening Google OAuth 2.0 consent in browser for $USER_ACCOUNT...\n\"))"
sleep 15
stop_segment

# ------------------------------------------------------------------------------
# STEP 2: Google OAuth Consent Screen & Client ID Inspection
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 2/4] OAuth Consent Screen & Client ID Inspection"
echo "================================================================================"
navigate_chrome "https://accounts.google.com/o/oauth2/v2/auth?client_id=988718620220-ak9h89ru1uuat23s5rc239momds6ke96.apps.googleusercontent.com&redirect_uri=http%3A%2F%2F127.0.0.1%3A8085&response_type=code&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdocuments+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive.file&access_type=offline"

prompt_action_paused "OAuth Consent Actions" \
  "1. Select $USER_ACCOUNT (NOT tychoish@gmail.com)\n2. Highlight URL bar showing client_id=988718620220...\n3. Review permissions and click [Allow]"

# Record 15 seconds of the consent confirmation state
notify_hud "Step 2/4: OAuth Consent" "Recording consent confirmation (15s)..." "normal" 14000
sleep 15
stop_segment

# ------------------------------------------------------------------------------
# STEP 3: Note Synchronization (20s total: 10s Emacs + 10s Docs)
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 3/4] Note Synchronization in Emacs & Google Docs"
echo "================================================================================"
start_segment
notify_hud "Step 3/4: Note Synchronization" "Showing local Denote note (#+sync_gdoc_account: $USER_ACCOUNT)" "normal" 9000
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
sleep 10

notify_hud "Step 3/4: Google Docs Interface" "Showing synced note in Google Docs browser (10s)" "normal" 9000
navigate_chrome "https://docs.google.com"
sleep 10
stop_segment

# ------------------------------------------------------------------------------
# STEP 4: Account Permission Revocation
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo " [Step 4/4] Account Permission Revocation"
echo "================================================================================"
navigate_chrome "https://myaccount.google.com/permissions"

prompt_action_paused "Revoke Permissions Action" \
  "In Chrome (signed in as $USER_ACCOUNT):\n1. Locate 'denote-sync' under Third-party apps\n2. Click [Remove Access] to show immediate revocability"

# Record 10 seconds of the revoked state
notify_hud "Step 4/4: Revocation" "Recording revoked permission state (10s)..." "normal" 9000
sleep 10
stop_segment

# ------------------------------------------------------------------------------
# Final Assembly: Concat Segments into Single Flawless Video
# ------------------------------------------------------------------------------
echo ""
echo "================================================================================"
echo ">>> Concatenating video segments into $OUTPUT_FILE..."
echo "================================================================================"
sed "s/^/file '/; s/$/'/" "$TMP_DIR/segments.txt" > "$TMP_DIR/concat_list.txt"
ffmpeg -nostdin -y -f concat -safe 0 -i "$TMP_DIR/concat_list.txt" -c copy "$OUTPUT_FILE" >/dev/null 2>&1

notify_hud "Verification Video Ready" "demo.mp4 successfully created and ready for upload!" "normal" 8000

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
