#!/bin/zsh
# Migrate the automatic relay from this Mac to rickymacmini.lan.
# Expected prompts: mini login password (ssh-copy-id), mini sudo password,
# then this Mac's sudo password to remove the local service.
set -eu
cd -- "${0:A:h}"
MINI_HOST=rickymacmini.lan
read 'MINI_USER?Mac mini username [rickymacmini]: '
MINI_USER=${MINI_USER:-rickymacmini}

echo '--- 1/4: install SSH key on the mini ---'
ssh-copy-id -i ~/.ssh/id_ed25519.pub "$MINI_USER@$MINI_HOST"

echo '--- 2/4: sync the tool to the mini ---'
ssh "$MINI_USER@$MINI_HOST" 'mkdir -p ~/ps5-portal-high-bitrate'
rsync -a --exclude .venv --exclude .git --exclude experiments --exclude auto-runtime \
  ./ "$MINI_USER@$MINI_HOST:~/ps5-portal-high-bitrate/"

echo '--- 3/4: install the service on the mini ---'
ssh -t "$MINI_USER@$MINI_HOST" 'cd ~/ps5-portal-high-bitrate && bash remote_install.sh'

echo '--- 4/4: stop and remove the service on THIS Mac ---'
touch auto-runtime/disabled 2>/dev/null || true
echo 'Waiting for the local relay to repair ARP and exit...'
sleep 40
sudo launchctl bootout system/com.portalbitrate.auto 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.portalbitrate.auto.plist
rm -f auto-runtime/disabled

echo
echo 'Done. The mini now patches Portal sessions automatically.'
echo 'Keep the mini awake: System Settings > Energy > prevent automatic sleep.'
read 'reply?Press Enter to close. '
