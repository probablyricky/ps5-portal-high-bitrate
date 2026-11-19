#!/bin/zsh
set -eu
cd -- "${0:A:h}"
.venv/bin/python portal_auto.py status --config auto-config.json --runtime auto-runtime
echo
sudo -n launchctl print "system/com.portalbitrate.auto" >/dev/null 2>&1 \
  && echo 'Service: installed' || echo 'Service: not installed (or check needs sudo)'
read 'reply?Press Enter to close. '
