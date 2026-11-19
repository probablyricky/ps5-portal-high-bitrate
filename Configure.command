#!/bin/zsh
set -eu
cd -- "${0:A:h}"
# Use the system Python: macOS 26+ restricts ARP table reads to Apple-signed
# binaries, and portal_discover.py only needs the standard library.
PY=/usr/bin/python3
[[ -x $PY ]] || PY=python3
"$PY" portal_discover.py
read 'reply?Press Enter to close. '
