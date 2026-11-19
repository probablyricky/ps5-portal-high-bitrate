#!/bin/bash
# Runs ON the Mac mini: venv, device discovery, baseline receipt, launchd install.
set -eu
cd "$(dirname "$0")"
LABEL=com.portalbitrate.auto
PLIST=/Library/LaunchDaemons/$LABEL.plist

PY=
for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 python3; do
  if command -v "$c" >/dev/null 2>&1 &&
     "$c" -c 'import sys; sys.exit(sys.version_info >= (3, 10))' 2>/dev/null; then
    PY=$c; break
  fi
done
if [[ -z $PY ]]; then
  PY=/usr/bin/python3
  echo "No Python 3.10+; using system $("$PY" --version 2>&1) (code is 3.9-compatible)."
fi
echo "Interpreter: $PY"
"$PY" -m venv .venv
.venv/bin/python -m pip install -r requirements.txt

# System python reads the ARP table on macOS 26+; discovery is stdlib-only.
/usr/bin/python3 portal_discover.py

mkdir -p auto-runtime
rm -f auto-runtime/disabled
.venv/bin/python - <<'PYEOF'
import datetime
from pathlib import Path
import portal_auto
c = portal_auto.config(Path('auto-config.json'))
portal_auto.atomic_json(Path('auto-runtime/auto-baseline.json'), {
    'time': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'fingerprint': portal_auto.fingerprint(c),
    'forwarded_out': 1,
    'restored': True,
    'source': 'manual portal_active_probe run verified this transport',
    'limit': 'Transport observed, not proof of picture quality or input responsiveness.'})
print('Baseline receipt written.')
PYEOF

sudo tee "$PLIST" > /dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(pwd)/.venv/bin/python</string>
        <string>$(pwd)/portal_auto.py</string>
        <string>run</string>
        <string>--config</string>
        <string>$(pwd)/auto-config.json</string>
        <string>--runtime</string>
        <string>$(pwd)/auto-runtime</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>$(pwd)/auto-runtime/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$(pwd)/auto-runtime/launchd.err.log</string>
</dict>
</plist>
PLIST
sudo chmod 644 "$PLIST"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST"
sleep 3
echo '--- mini relay status ---'
cat auto-runtime/status.json 2>/dev/null || tail -20 auto-runtime/launchd.err.log || true
