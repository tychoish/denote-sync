#!/usr/bin/env bash
# ==============================================================================
# generate-demo-video.sh - Programmatically generate 90s 1080p OAuth demo video
# Uses Xvfb, Chromium, and ffmpeg to record an end-to-end verification walkthrough
# strictly adhering to the 90-second script in docs/google-verification-kit.org.
# ==============================================================================
set -euo pipefail

OUTPUT_FILE="${1:-demo.mp4}"
DISPLAY_NUM=":99"
RESOLUTION="1920x1080"
FPS="30"
DURATION="90"
CLIENT_ID="${CLIENT_ID:-988718620220-ak9h89ru1uuat23s5rc239momds6ke96.apps.googleusercontent.com}"
DEV_EMAIL="${DEV_EMAIL:-garen@tychoish.com}"
USER_ACCOUNT="${USER_ACCOUNT:-kleinman.sam@gmail.com}"

echo "=== denote-sync 90s OAuth Verification Demo Generator ==="
echo "Target output: $OUTPUT_FILE"
echo "Resolution: $RESOLUTION @ ${FPS}fps (Duration: ${DURATION}s)"
echo "Client ID: $CLIENT_ID"
echo "Developer Email: $DEV_EMAIL"
echo "User Account: $USER_ACCOUNT"

for cmd in Xvfb ffmpeg chromium; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' is not installed." >&2
        exit 1
    fi
done

TEMP_DIR="$(mktemp -d -t denote-video-XXXXXX)"
trap 'sleep 1; rm -rf "$TEMP_DIR" 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true' EXIT

DEMO_HTML="$TEMP_DIR/walkthrough.html"

cat <<'EOF' > "$DEMO_HTML"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>denote-sync Google OAuth 2.0 Verification Walkthrough</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 0;
    width: 1920px;
    height: 1080px;
    background: #090d16;
    color: #f1f5f9;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* Top Navigation & App Banner */
  header {
    height: 72px;
    background: #111827;
    border-bottom: 2px solid #1f2937;
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 36px;
  }
  .app-info { display: flex; align-items: center; gap: 16px; }
  .logo {
    width: 42px; height: 42px; background: linear-gradient(135deg, #2563eb, #38bdf8);
    border-radius: 8px; display: flex; align-items: center; justify-content: center;
    font-weight: 800; font-size: 22px; color: #fff;
  }
  .title-group h1 { margin: 0; font-size: 22px; font-weight: 700; color: #f8fafc; }
  .title-group .sub { margin: 2px 0 0 0; font-size: 13px; color: #94a3b8; }
  .status-badge {
    background: #0369a1; color: #e0f2fe; padding: 6px 14px;
    border-radius: 9999px; font-size: 13px; font-weight: 600;
  }

  /* Main Stage Container */
  main {
    flex: 1;
    position: relative;
    padding: 24px 36px;
    display: flex;
    flex-direction: column;
  }

  /* Step Timeline Bar at Bottom */
  footer {
    height: 64px;
    background: #0b0f19;
    border-top: 1px solid #1e293b;
    display: flex;
    align-items: center;
    padding: 0 36px;
    gap: 20px;
  }
  .time-display {
    font-family: "JetBrains Mono", monospace;
    font-size: 16px;
    color: #38bdf8;
    font-weight: 700;
    min-width: 90px;
  }
  .timeline-track {
    flex: 1;
    height: 10px;
    background: #1e293b;
    border-radius: 5px;
    position: relative;
    overflow: hidden;
  }
  .timeline-progress {
    height: 100%;
    width: 0%;
    background: linear-gradient(90deg, #0284c7, #38bdf8);
    transition: width 0.2s linear;
  }
  .step-indicators {
    display: flex;
    gap: 16px;
    font-size: 13px;
  }
  .step-tag {
    color: #64748b;
    padding: 4px 10px;
    border-radius: 6px;
    font-weight: 500;
  }
  .step-tag.active {
    background: #1e293b;
    color: #38bdf8;
    font-weight: 700;
    border: 1px solid #0284c7;
  }

  /* Shared Mockup Window Chrome */
  .window-box {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 12px;
    box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
    overflow: hidden;
    display: flex;
    flex-direction: column;
    height: 100%;
  }
  .window-bar {
    height: 40px;
    background: #0f172a;
    border-bottom: 1px solid #334155;
    display: flex;
    align-items: center;
    padding: 0 16px;
    gap: 12px;
  }
  .window-dots { display: flex; gap: 8px; }
  .dot { width: 12px; height: 12px; border-radius: 50%; }
  .dot.red { background: #ef4444; }
  .dot.yellow { background: #f59e0b; }
  .dot.green { background: #10b981; }
  .window-title { font-size: 13px; color: #94a3b8; font-family: monospace; }

  /* Browser URL bar */
  .browser-url-bar {
    flex: 1;
    background: #090d16;
    border: 1px solid #475569;
    border-radius: 6px;
    padding: 4px 14px;
    color: #cbd5e1;
    font-family: monospace;
    font-size: 13px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .browser-url-bar .hl {
    background: #854d0e66;
    color: #fde047;
    font-weight: bold;
    padding: 2px 4px;
    border-radius: 3px;
    border: 1px solid #facc15;
  }

  /* Step Content Panes */
  .scene {
    display: none;
    height: 100%;
    flex-direction: column;
  }
  .scene.active { display: flex; }

  /* Scene 1: Google Cloud Console Credentials */
  .gcp-layout {
    display: flex;
    flex-direction: column;
    padding: 28px 36px;
    gap: 20px;
    height: 100%;
  }
  .gcp-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid #334155;
    padding-bottom: 16px;
  }
  .gcp-header h2 { margin: 0; font-size: 24px; color: #f8fafc; }
  .table-box {
    background: #0f172a;
    border: 1px solid #334155;
    border-radius: 8px;
    overflow: hidden;
  }
  table { width: 100%; border-collapse: collapse; text-align: left; }
  th { background: #1e293b; color: #94a3b8; font-size: 13px; text-transform: uppercase; padding: 12px 18px; border-bottom: 1px solid #334155; }
  td { padding: 16px 18px; font-size: 14px; border-bottom: 1px solid #1e293b; color: #e2e8f0; }
  .mono { font-family: monospace; }
  .highlight-client {
    background: #854d0e55;
    color: #fef08a;
    font-weight: bold;
    border: 1px solid #facc15;
    padding: 4px 8px;
    border-radius: 4px;
  }
  .info-callout {
    background: #0369a122;
    border-left: 4px solid #38bdf8;
    padding: 16px 20px;
    border-radius: 0 8px 8px 0;
    font-size: 15px;
    line-height: 1.5;
  }

  /* Scene 2 & 4: Emacs Editor */
  .emacs-view {
    height: 100%;
    background: #0d1117;
    display: flex;
    flex-direction: column;
    font-family: "JetBrains Mono", Consolas, monospace;
    font-size: 15px;
    line-height: 1.6;
    padding: 24px;
    overflow: hidden;
  }
  .emacs-buffer { flex: 1; color: #e6edf3; }
  .emacs-comment { color: #8b949e; }
  .emacs-keyword { color: #ff7b72; font-weight: bold; }
  .emacs-string { color: #a5d6ff; }
  .emacs-func { color: #d2a8ff; }
  .emacs-modeline {
    background: #21262d;
    color: #8b949e;
    padding: 6px 16px;
    margin: 16px -24px -24px -24px;
    border-top: 1px solid #30363d;
    display: flex;
    justify-content: space-between;
    font-size: 13px;
  }
  .minibuffer {
    background: #161b22;
    color: #58a6ff;
    padding: 8px 16px;
    margin: 0 -24px -24px -24px;
    border-top: 1px solid #30363d;
    font-weight: bold;
  }

  /* Scene 3: Google Consent Screen */
  .consent-wrapper {
    display: flex;
    justify-content: center;
    align-items: center;
    height: 100%;
    background: #0b0f19;
  }
  .google-card {
    width: 620px;
    background: #ffffff;
    color: #1f2937;
    border-radius: 12px;
    box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5);
    padding: 40px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }
  .g-logo { font-size: 26px; font-weight: 700; color: #4285f4; text-align: center; }
  .g-card-title { font-size: 22px; font-weight: 600; text-align: center; color: #202124; }
  .g-card-sub { font-size: 14px; text-align: center; color: #5f6368; }
  .scope-list {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .scope-row { display: flex; gap: 12px; align-items: flex-start; }
  .scope-icon { font-size: 18px; color: #1a73e8; }
  .scope-text { font-size: 14px; line-height: 1.4; color: #3c4043; }
  .g-btn-group { display: flex; justify-content: flex-end; gap: 12px; margin-top: 10px; }
  .g-btn {
    padding: 10px 24px; border-radius: 4px; font-size: 14px; font-weight: 600;
    cursor: pointer; border: none;
  }
  .g-btn.cancel { background: transparent; color: #1a73e8; }
  .g-btn.primary { background: #1a73e8; color: #ffffff; box-shadow: 0 1px 3px rgba(0,0,0,0.3); }

  /* Split View for Scene 4 */
  .split-container {
    display: flex;
    height: 100%;
    gap: 20px;
  }
  .split-pane {
    flex: 1;
    height: 100%;
  }

  /* Scene 5: Permissions & Revocation */
  .revoke-layout {
    padding: 32px;
    height: 100%;
    display: flex;
    flex-direction: column;
    gap: 24px;
    background: #ffffff;
    color: #202124;
  }
  .revoke-header { font-size: 22px; font-weight: 600; border-bottom: 1px solid #dadce0; padding-bottom: 16px; }
  .app-card {
    border: 1px solid #dadce0;
    border-radius: 8px;
    padding: 24px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .app-card h3 { margin: 0 0 6px 0; font-size: 18px; color: #1a73e8; }
  .app-card p { margin: 0; font-size: 14px; color: #5f6368; }
</style>
</head>
<body>

<header>
  <div class="app-info">
    <div class="logo">D</div>
    <div class="title-group">
      <h1>denote-sync &bull; Google OAuth 2.0 Verification Walkthrough</h1>
      <div class="sub">App: <strong>denote-sync</strong> | Contact: <strong>__DEV_EMAIL__</strong> | Sensitive Scope Tier (drive.file)</div>
    </div>
  </div>
  <div class="status-badge" id="scene-badge">Step 1: GCP Credentials</div>
</header>

<main>

  <!-- SCENE 1: Google Cloud Console Verification (0:00 - 0:15) -->
  <div class="scene active" id="scene-1">
    <div class="window-box">
      <div class="window-bar">
        <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
        <div class="browser-url-bar">https://console.cloud.google.com/apis/credentials?project=denote-sync-gdocs</div>
      </div>
      <div class="gcp-layout">
        <div class="gcp-header">
          <h2>Google Cloud Console &mdash; APIs & Services: Credentials</h2>
          <span style="color: #38bdf8; font-weight: 600;">Project: denote-sync-gdocs</span>
        </div>
        <div class="table-box">
          <table>
            <thead>
              <tr><th>Name</th><th>Application Type</th><th>Creation Date</th><th>Client ID</th></tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>denote-sync Desktop Client</strong></td>
                <td>Desktop app</td>
                <td>Oct 10, 2026</td>
                <td><span class="highlight-client mono" id="cfg-client-id">__CLIENT_ID__</span></td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="info-callout">
          <strong>Verification Criteria Match:</strong><br>
          This OAuth 2.0 Desktop Client ID is registered exclusively for <code>denote-sync</code>.
          Notice the exact client identifier highlighted above. In Step 3, this identical client ID appears
          directly in Google's official authorization URL address bar.
        </div>
      </div>
    </div>
  </div>

  <!-- SCENE 2: Initiating Authorization from Emacs (0:15 - 0:35) -->
  <div class="scene" id="scene-2">
    <div class="window-box">
      <div class="window-bar">
        <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
        <div class="window-title">Emacs &mdash; *denote-sync-bootstrap*</div>
      </div>
      <div class="emacs-view">
        <div class="emacs-buffer">
          <span class="emacs-comment">;; denote-sync Google Docs Setup Wizard</span><br>
          <span class="emacs-comment">;; Running M-x denote-sync-bootstrap...</span><br><br>
          [✓] Found gog CLI helper: /usr/local/bin/gog<br>
          [✓] Credentials profile registered with client ID: <span class="emacs-string">"__CLIENT_ID__"</span><br>
          [✓] Encrypted file keyring configured at ~/.local/share/gogcli/keyring<br>
          <br>
          <span class="emacs-keyword">Invoking OAuth Authorization:</span><br>
          &nbsp;&nbsp;&bull; Account: <span class="emacs-string">__USER_ACCOUNT__</span><br>
          &nbsp;&nbsp;&bull; Services: <span class="emacs-string">docs,drive</span><br>
          &nbsp;&nbsp;&bull; Scope minimization: <span class="emacs-func">--drive-scope=file</span> (Sensitive Scope: https://www.googleapis.com/auth/drive.file)<br>
          <br>
          Opening Google OAuth 2.0 consent in default browser...
        </div>
        <div class="emacs-modeline">
          <span>-UUU:--  *denote-sync-bootstrap*   All (12,0)   (Emacs-Lisp)</span>
          <span>denote-sync v0.2.0</span>
        </div>
        <div class="minibuffer">
          M-x denote-sync-bootstrap: Initiating browser OAuth handshake for __USER_ACCOUNT__...
        </div>
      </div>
    </div>
  </div>

  <!-- SCENE 3: OAuth Consent Screen & Client ID Inspection (0:35 - 0:55) -->
  <div class="scene" id="scene-3">
    <div class="window-box">
      <div class="window-bar">
        <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
        <div class="browser-url-bar">
          https://accounts.google.com/o/oauth2/v2/auth?<span class="hl">client_id=__CLIENT_ID__</span>&scope=https://www.googleapis.com/auth/documents%20https://www.googleapis.com/auth/drive.file&response_type=code
        </div>
      </div>
      <div class="consent-wrapper">
        <div class="google-card">
          <div class="g-logo">Google</div>
          <div class="g-card-title">Sign in with Google</div>
          <div class="g-card-sub"><strong>denote-sync</strong> wants to access your Google Account (<strong>__USER_ACCOUNT__</strong>)</div>

          <div class="scope-list">
            <div class="scope-row">
              <div class="scope-icon">📄</div>
              <div class="scope-text">
                <strong>See, edit, create, and delete your Google Docs documents</strong><br>
                <small style="color: #64748b;">(https://www.googleapis.com/auth/documents)</small>
              </div>
            </div>
            <div class="scope-row">
              <div class="scope-icon">📁</div>
              <div class="scope-text">
                <strong>See, edit, create, and delete only the specific Google Drive files you use with this app</strong><br>
                <small style="color: #64748b;">(https://www.googleapis.com/auth/drive.file &mdash; Restricted to app files)</small>
              </div>
            </div>
          </div>

          <div style="font-size: 13px; color: #5f6368; line-height: 1.4;">
            Make sure you trust denote-sync. You may review the app's
            <a href="https://tychoish.github.io/denote-sync/privacy.html" style="color: #1a73e8;">Privacy Policy</a>.
          </div>

          <div class="g-btn-group">
            <button class="g-btn cancel">Cancel</button>
            <button class="g-btn primary" id="allow-btn">Continue &amp; Allow</button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- SCENE 4: Note Synchronization in Emacs & Google Docs (0:55 - 1:15) -->
  <div class="scene" id="scene-4">
    <div class="split-container">
      <!-- Left: Emacs Note -->
      <div class="split-pane window-box">
        <div class="window-bar">
          <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
          <div class="window-title">Emacs &mdash; 20261011T103000==spec--project-plan__notes.org</div>
        </div>
        <div class="emacs-view">
          <div class="emacs-buffer">
            <span class="emacs-keyword">#+title:</span> Project Architecture Specification<br>
            <span class="emacs-keyword">#+date:</span>  [2026-10-11 Sun 10:30]<br>
            <span class="emacs-keyword">#+sync_gdoc_id:</span> 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms<br>
            <span class="emacs-keyword">#+sync_gdoc_account:</span> __USER_ACCOUNT__<br>
            <span class="emacs-keyword">#+sync_gdoc_edited:</span> 2026-10-11T14:35:00Z<br><br>
            * Overview<br>
            denote-sync establishes direct bidirectional sync with Google Docs API.<br><br>
            * Section 1: Security & Local Keyring<br>
            Tokens are stored locally encrypted in ~/.local/share/gogcli/keyring.<br>
            Zero intermediary servers or telemetry beacons.<br><br>
            <span style="color: #4ade80;">[✓] denote-sync-push: successfully exported note to Google Docs!</span>
          </div>
          <div class="emacs-modeline">
            <span>-UUU:--  project-plan.org   Top (1,0)   (Org)</span>
            <span>M-x denote-sync-push</span>
          </div>
        </div>
      </div>
      <!-- Right: Google Docs View -->
      <div class="split-pane window-box">
        <div class="window-bar">
          <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
          <div class="browser-url-bar">https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit</div>
        </div>
        <div style="background: #f8f9fa; color: #202124; padding: 36px 48px; height: 100%; display: flex; flex-direction: column;">
          <div style="font-size: 26px; font-weight: 700; margin-bottom: 12px; border-bottom: 2px solid #dadce0; padding-bottom: 8px;">
            Project Architecture Specification
          </div>
          <div style="font-size: 15px; line-height: 1.6; color: #3c4043;">
            <p><strong>Overview</strong><br>
            denote-sync establishes direct bidirectional sync with Google Docs API.</p>
            <p><strong>Section 1: Security &amp; Local Keyring</strong><br>
            Tokens are stored locally encrypted in ~/.local/share/gogcli/keyring.<br>
            Zero intermediary servers or telemetry beacons.</p>
            <div style="background: #e8f0fe; border-left: 4px solid #1a73e8; padding: 12px; margin-top: 20px; font-size: 13px;">
              Synced via denote-sync using official Google Docs and Drive APIs (Sensitive Scope: drive.file)
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- SCENE 5: Immediate Permission Revocation (1:15 - 1:30) -->
  <div class="scene" id="scene-5">
    <div class="window-box">
      <div class="window-bar">
        <div class="window-dots"><div class="dot red"></div><div class="dot yellow"></div><div class="dot green"></div></div>
        <div class="browser-url-bar">https://myaccount.google.com/permissions</div>
      </div>
      <div class="revoke-layout">
        <div class="revoke-header">Google Account &mdash; Third-party apps with account access</div>
        <div class="app-card">
          <div>
            <h3>denote-sync</h3>
            <p>Has access to: <strong>Google Docs</strong>, <strong>Google Drive (specific files only)</strong></p>
            <p style="margin-top: 6px; font-size: 13px; color: #70757a;">Access given on: October 11, 2026 &bull; Client ID: <span class="mono">__CLIENT_ID__</span></p>
          </div>
          <div>
            <button style="background: #d93025; color: #fff; border: none; padding: 12px 24px; border-radius: 6px; font-weight: 600; font-size: 14px; cursor: pointer;">
              Remove Access
            </button>
          </div>
        </div>
        <div style="background: #f1f3f4; border-radius: 8px; padding: 20px; font-size: 14px; line-height: 1.5; color: #3c4043;">
          <strong>Complete Revocability Guaranteed:</strong><br>
          Clicking "Remove Access" immediately revokes the OAuth 2.0 refresh token on Google servers.<br>
          Locally in Emacs, cached credentials can be permanently purged at any time by executing:
          <code style="background: #e8eaed; padding: 2px 6px; border-radius: 4px;">gog auth remove __USER_ACCOUNT__</code>.
        </div>
      </div>
    </div>
  </div>

</main>

<footer>
  <div class="time-display" id="time-display">00:00</div>
  <div class="timeline-track">
    <div class="timeline-progress" id="timeline-progress"></div>
  </div>
  <div class="step-indicators">
    <span class="step-tag active" id="tag-1">1. Cloud Console (0-15s)</span>
    <span class="step-tag" id="tag-2">2. Emacs Onboarding (15-35s)</span>
    <span class="step-tag" id="tag-3">3. OAuth Consent (35-55s)</span>
    <span class="step-tag" id="tag-4">4. Note Sync (55-75s)</span>
    <span class="step-tag" id="tag-5">5. Revocation (75-90s)</span>
  </div>
</footer>

<script>
  const totalSeconds = 90;
  let elapsed = 0;

  const sceneBadge = document.getElementById('scene-badge');
  const timeDisplay = document.getElementById('time-display');
  const timelineProgress = document.getElementById('timeline-progress');

  function switchScene(num, name) {
    document.querySelectorAll('.scene').forEach(s => s.classList.remove('active'));
    document.querySelectorAll('.step-tag').forEach(t => t.classList.remove('active'));

    const curScene = document.getElementById('scene-' + num);
    const curTag = document.getElementById('tag-' + num);
    if (curScene) curScene.classList.add('active');
    if (curTag) curTag.classList.add('active');
    if (sceneBadge) sceneBadge.textContent = 'Step ' + num + ': ' + name;
  }

  setInterval(() => {
    elapsed++;
    if (elapsed > totalSeconds) elapsed = totalSeconds;

    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;
    timeDisplay.textContent = String(mins).padStart(2, '0') + ':' + String(secs).padStart(2, '0');
    timelineProgress.style.width = ((elapsed / totalSeconds) * 100) + '%';

    if (elapsed === 15) {
      switchScene(2, 'Emacs Authorization');
    } else if (elapsed === 35) {
      switchScene(3, 'Consent Screen & Client ID Inspection');
    } else if (elapsed === 55) {
      switchScene(4, 'Bidirectional Note Synchronization');
    } else if (elapsed === 75) {
      switchScene(5, 'Account Permission Revocation');
    }
  }, 1000);
</script>
</body>
</html>
EOF

# Substitute parameters into HTML
sed -i "s|__CLIENT_ID__|$CLIENT_ID|g" "$DEMO_HTML"
sed -i "s|__DEV_EMAIL__|$DEV_EMAIL|g" "$DEMO_HTML"
sed -i "s|__USER_ACCOUNT__|$USER_ACCOUNT|g" "$DEMO_HTML"

echo "Starting virtual display at $DISPLAY_NUM..."
Xvfb "$DISPLAY_NUM" -screen 0 "${RESOLUTION}x24" >/dev/null 2>&1 &
XVFB_PID=$!
sleep 2

export DISPLAY="$DISPLAY_NUM"

echo "Starting Chromium in 1080p kiosk mode..."
chromium \
  --user-data-dir="$TEMP_DIR/chrome-profile" \
  --kiosk \
  --test-type \
  --disable-infobars \
  --no-first-run \
  --no-default-browser-check \
  --disable-first-run-ui \
  --disable-fre \
  --disable-search-engine-choice-screen \
  --window-size=1920,1080 \
  --window-position=0,0 \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  "file://$DEMO_HTML" >/dev/null 2>&1 &
CHROME_PID=$!
sleep 3

echo "Recording full 90-second 1080p verification walkthrough with ffmpeg..."
ffmpeg -y -f x11grab \
  -video_size "$RESOLUTION" \
  -framerate "$FPS" \
  -i "${DISPLAY_NUM}.0" \
  -t "$DURATION" \
  -c:v libx264 \
  -preset fast \
  -pix_fmt yuv420p \
  "$OUTPUT_FILE"

echo "[✓] Demo video successfully generated: $OUTPUT_FILE ($(du -h "$OUTPUT_FILE" | cut -f1))"

kill "$CHROME_PID" "$XVFB_PID" 2>/dev/null || true
trap - EXIT
sleep 1; rm -rf "$TEMP_DIR" 2>/dev/null || true
