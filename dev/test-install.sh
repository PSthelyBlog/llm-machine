#!/usr/bin/env bash
# Install from the ISO onto a blank disk, answering the installer the way a person would,
# then boot the installed system and stop at the Claude sign-in. Screenshots go to .vm/.
# usage: dev/test-install.sh [--encrypt] [--french]
set -euo pipefail
cd "$(dirname "$0")/.."

encrypt=no french=no
for arg in "$@"; do
  case "$arg" in
    --encrypt) encrypt=yes ;;
    --french) french=yes ;;
    *)
      echo "usage: dev/test-install.sh [--encrypt] [--french]" >&2
      exit 1
      ;;
  esac
done
passphrase=disk-pass-123
qmp() { python3 dev/qmp.py "$sock" "$@"; }
shot() { qmp screenshot "$PWD/.vm/$1.png" && echo "screenshot .vm/$1.png"; }
wait_sock() { for _ in $(seq 60); do [ -S "$sock" ] && return; sleep 1; done; exit 1; }

nix build .#iso --no-link
sock=.vm/qmp-install.sock
nix run .#iso-vm -- --reset --headless > .vm/test-install.out 2>&1 &
vm=$!
wait_sock
sleep 50
if [ "$french" = yes ]; then
  qmp key down down down down # from English (US) to French in the sorted list
  export QMP_KEYMAP=fr        # how the installer's console types from now on
  passphrase=disk-pass-é123   # an accent, to check the boot screen uses the same layout
fi
shot install-1-keyboard
qmp key ret
sleep 6
shot install-2-disk
qmp key ret # the only disk
sleep 2
qmp type 'ERASE\n'
sleep 2
if [ "$encrypt" = yes ]; then
  qmp type y
  sleep 1
  qmp type "$passphrase\n"
  sleep 1
  qmp type "$passphrase\n"
else
  qmp type n
fi
sleep 2
qmp type 'Ada Lovelace\n'
sleep 1
qmp key ret # suggested username
sleep 1
qmp type 'user-pass\n'
sleep 1
qmp type 'user-pass\n'
sleep 1
qmp key ret # suggested computer name
sleep 2
shot install-3-summary
qmp type y
sleep 30
shot install-4-progress
# The last screen waits for Enter, then reboots, which ends the VM (-no-reboot).
for _ in $(seq 120); do
  kill -0 "$vm" 2>/dev/null || break
  qmp key ret 2>/dev/null || true
  sleep 10
done
if kill -0 "$vm" 2>/dev/null; then
  shot install-5-stuck
  echo "the installer did not finish within 20 minutes" >&2
  exit 1
fi
echo "installed"

sock=.vm/qmp-install.sock
nix run .#iso-vm -- --disk-only --headless > .vm/test-firstboot.out 2>&1 &
wait_sock
sleep 20
if [ "$encrypt" = yes ]; then
  shot firstboot-1-passphrase
  qmp type "$passphrase\n"
fi
sleep 45
shot firstboot-2-tty1
echo "the installed system is running; quit it with: python3 dev/qmp.py .vm/qmp-install.sock key ctrl-alt-delete, or kill QEMU"
