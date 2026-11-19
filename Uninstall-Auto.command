#!/bin/zsh
set -eu
cd -- "${0:A:h}"
LABEL=com.portalbitrate.auto

.venv/bin/python - <<'PYEOF' || true
from pathlib import Path
Path('auto-runtime').mkdir(exist_ok=True)
Path('auto-runtime/disabled').touch()
print('Stop marker written; relay will exit and repair ARP within seconds.')
PYEOF
sleep 40
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo rm -f "/Library/LaunchDaemons/$LABEL.plist"
printf '\nAutomatic relay removed. Reconnect the Portal once to refresh its ARP.\n'
read 'reply?Press Enter to close. '
