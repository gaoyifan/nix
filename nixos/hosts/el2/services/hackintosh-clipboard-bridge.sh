#!/usr/bin/env bash
set -euo pipefail

ssh_options=(
  -i /run/agenix/icloud-photos-ssh-key
  -o IdentityAgent=none
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=5
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=2
  -o ControlMaster=auto
  -o "ControlPath=$RUNTIME_DIRECTORY/ssh"
  -o ControlPersist=60
)

cd "$RUNTIME_DIRECTORY"

# Preserve the guest clipboard when the bridge starts or reconnects.
ssh -n "${ssh_options[@]}" yifan@100.64.2.80 /usr/bin/pbpaste >last
xclip -selection clipboard -in <last
echo "Hackintosh clipboard bridge connected"

while sleep 0.5; do
  ssh -n "${ssh_options[@]}" yifan@100.64.2.80 /usr/bin/pbpaste >guest

  # A selection containing only images has no UTF8_STRING target.
  if xclip -selection clipboard -out -target UTF8_STRING >console 2>/dev/null && ! cmp -s console last; then
    ssh "${ssh_options[@]}" yifan@100.64.2.80 /usr/bin/pbcopy <console
    cp console last
  elif ! cmp -s guest last; then
    xclip -selection clipboard -in <guest
    cp guest last
  fi
done
