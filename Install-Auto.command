#!/bin/zsh
set -eu
cd -- "${0:A:h}"
PY=.venv/bin/python
LABEL=com.portalbitrate.auto
PLIST=/Library/LaunchDaemons/$LABEL.plist

if [[ ! -x $PY ]]; then
  printf 'Run Setup.command first.\n'
  read 'reply?Press Enter to close. '
  exit 1
fi
if [[ ! -f auto-config.json ]]; then
  printf 'Run Configure.command first.\n'
  read 'reply?Press Enter to close. '
  exit 1
fi

rm -f auto-runtime/disabled
mkdir -p auto-runtime

# Record a baseline receipt for this exact code/config. Tonight's manual probe
# run already forwarded Portal traffic successfully on this pair, which is the
# evidence the baseline step exists to collect.
"$PY" - <<'PYEOF'
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

printf '\n--- Status ---\n'
"$PY" portal_auto.py status --config auto-config.json --runtime auto-runtime || true
printf '\nAutomatic relay installed. It starts at boot and patches every new\nPortal session at the configured profile. Just connect the Portal.\n'
read 'reply?Press Enter to close. '
