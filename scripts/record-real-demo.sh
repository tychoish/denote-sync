#!/usr/bin/env bash
# ==============================================================================
# record-real-demo.sh - Interactive 1080p Desktop Recorder for Google Verification
# Records live, non-simulated desktop actions across Emacs, Google Cloud Console,
# Google OAuth Consent, and Google Docs.
# ==============================================================================
set -euo pipefail

OUTPUT_FILE="${1:-demo.mp4}"
DISPLAY_TARGET="${DISPLAY:-:0}"
TARGET_WIDTH=1920
TARGET_HEIGHT=1080
TARGET_FPS=30

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is required but not installed." >&2
    exit 1
fi

# Detect display geometry
SCREEN_RES=$(xdpyinfo -display "$DISPLAY_TARGET" 2>/dev/null | awk '/dimensions:/ {print $2}' || true)
if [ -z "$SCREEN_RES" ]; then
    SCREEN_RES=$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}' || true)
fi
SCREEN_RES="${SCREEN_RES:-1920x1200}"

echo "================================================================================"
echo "    denote-sync Google OAuth 2.0 Live Desktop Verification Recorder"
echo "================================================================================"
echo "Output file:        $OUTPUT_FILE"
echo "Target Display:     $DISPLAY_TARGET ($SCREEN_RES)"
echo "Target Format:      ${TARGET_WIDTH}x${TARGET_HEIGHT} @ ${TARGET_FPS}fps (1080p H.264)"
echo "--------------------------------------------------------------------------------"
echo "This script will record your real screen while you perform the 5 walkthrough"
echo "steps specified in docs/google-verification-kit.org:"
echo ""
echo "  [Step 1 ~15s] Google Cloud Console:"
echo "                Show APIs & Services -> Credentials tab with OAuth 2.0 Client ID."
echo ""
echo "  [Step 2 ~20s] Emacs Initiation:"
echo "                Switch to Emacs, run M-x denote-sync-gdocs-setup or denote-sync-bootstrap."
echo ""
echo "  [Step 3 ~20s] Consent Screen & Client ID:"
echo "                Browser opens Google OAuth consent screen. Point your cursor to the"
echo "                URL bar showing client_id=..., review sensitive scopes, click Allow."
echo ""
echo "  [Step 4 ~20s] Bidirectional Sync:"
echo "                In Emacs, run M-x denote-sync-push. Switch to Google Docs to show"
echo "                the created document. Make an edit, run M-x denote-sync-pull."
echo ""
echo "  [Step 5 ~15s] Permission Revocation:"
echo "                Open https://myaccount.google.com/permissions, click denote-sync,"
echo "                and click 'Remove Access' to show user revocability."
echo "================================================================================"
echo ""
read -r -p "Ready? Press [ENTER] to start 5-second countdown (or Ctrl+C to abort)..."

echo ""
for i in 5 4 3 2 1; do
    echo -ne "\r>>> Recording starts in $i seconds... (Switch to Google Cloud Console now!) "
    sleep 1
done
echo -e "\r>>> [RECORDING STARTED] Perform the 5 steps now. Press [ENTER] or Ctrl+C when finished.\n"

# Run ffmpeg in background
# Uses letterboxed scaling (pad/scale) to cleanly map any native resolution (e.g. 1920x1200) to standard 1920x1080
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

stop_recording() {
    echo ""
    echo ">>> Stopping recorder and finalizing MP4 container..."
    if kill -0 "$FFMPEG_PID" 2>/dev/null; then
        kill -INT "$FFMPEG_PID" 2>/dev/null || true
        wait "$FFMPEG_PID" 2>/dev/null || true
    fi
}
trap stop_recording EXIT INT TERM

# Live timer loop
START_TIME=$(date +%s)
while kill -0 "$FFMPEG_PID" 2>/dev/null; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    MINS=$((ELAPSED / 60))
    SECS=$((ELAPSED % 60))
    
    STEP="Step 1: Cloud Console"
    if [ "$ELAPSED" -ge 75 ]; then
        STEP="Step 5: Revoke Permissions"
    elif [ "$ELAPSED" -ge 55 ]; then
        STEP="Step 4: Bidirectional Sync"
    elif [ "$ELAPSED" -ge 35 ]; then
        STEP="Step 3: Consent Screen & URL"
    elif [ "$ELAPSED" -ge 15 ]; then
        STEP="Step 2: Emacs Authorization"
    fi

    printf "\rElapsed: %02d:%02d / ~01:30 | Current: %-32s [Press ENTER to Stop]" "$MINS" "$SECS" "$STEP"
    
    # Check if user pressed enter (with 1s timeout)
    if read -t 1 -r; then
        break
    fi
done

trap - EXIT INT TERM
stop_recording

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
    echo "Next Step: Review the video, then upload to YouTube as 'Unlisted' and include"
    echo "the YouTube URL in your Google Cloud OAuth verification request."
else
    echo "[✗] Recording failed to produce $OUTPUT_FILE."
fi
echo "================================================================================"
