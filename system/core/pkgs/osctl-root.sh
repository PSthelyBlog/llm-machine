# osctl-root: the privileged half of osctl, run through sudo.
# It only ever activates a built NixOS system or moves between existing generations;
# the unprivileged osctl does the building and the git bookkeeping.

PROFILE=/nix/var/nix/profiles/system
RUN=/run/osctl           # trial state that must not survive a reboot
LIB=/var/lib/osctl       # reboot-trial state that must
GCROOT=/nix/var/nix/gcroots/osctl-pending
SELF=$(readlink -f "$0") # a store path, so the revert timer keeps running this exact script

die() {
  echo "osctl-root: $*" >&2
  exit 1
}

[ "$(id -u)" = 0 ] || die "must run as root"

check_system() {
  case "$1" in
    /nix/store/*) ;;
    *) die "not a store path: $1" ;;
  esac
  [ -x "$1/bin/switch-to-configuration" ] && [ -f "$1/nixos-version" ] || die "not a NixOS system: $1"
}

current_gen() { readlink "$PROFILE" 2>/dev/null | sed -E 's/^system-([0-9]+)-link$/\1/' || true; }
gen_path() { readlink -f "$PROFILE-$1-link"; }
pending() { cat "$RUN/pending" 2>/dev/null || true; }
nothing_pending() { [ -z "$(pending)" ] && [ ! -e "$LIB/pending-boot" ]; }

announce() {
  logger -t osctl "$*"
  wall "$*" 2>/dev/null || true
}

# systemd-boot names entries after a hash of their content, so find the generation's
# entry by the init= path it boots.
boot_entry() {
  local init
  init="$(gen_path "$1")/init"
  { grep -lF "options init=$init " /boot/loader/entries/nixos-*.conf 2>/dev/null || true; } |
    head -n1 | xargs -r basename | sed -E 's/\+[0-9]+(-[0-9]+)?\.conf$/.conf/'
}

activate() { # system action -> exit status of switch-to-configuration
  local rc=0
  "$1/bin/switch-to-configuration" "$2" || rc=$?
  return "$rc"
}

cmd_try() {
  local sys=${1:-} timeout=${2:-}
  check_system "$sys"
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -ge 10 ] || die "timeout must be at least 10 seconds"
  nothing_pending || die "a change is already pending"

  mkdir -p "$RUN"
  readlink -f /run/current-system > "$RUN/previous"
  echo "$sys" > "$RUN/pending"
  echo $(($(date +%s) + timeout)) > "$RUN/deadline"
  ln -sfn "$sys" "$GCROOT"

  # Arm the dead-man switch first: if activation breaks the display or the network,
  # nobody may be able to run 'osctl revert'.
  systemctl reset-failed osctl-revert.timer osctl-revert.service 2>/dev/null || true
  if ! systemd-run --quiet --unit=osctl-revert --description="osctl: revert an unconfirmed change" \
    --on-active="${timeout}s" --timer-property=AccuracySec=1s \
    "$SELF" revert --expired; then
    rm -f "$RUN/pending" "$RUN/deadline" "$RUN/previous" "$GCROOT"
    die "could not arm the revert timer; nothing was changed"
  fi

  local rc=0
  activate "$sys" test || rc=$?
  case "$rc" in
    0) ;;
    4)
      echo "osctl-root: the change is active, but some units failed to start (see systemctl --failed)." >&2
      exit 4
      ;;
    *)
      echo "osctl-root: activation failed (exit $rc); reverting." >&2
      cmd_revert
      exit 1
      ;;
  esac
}

cmd_confirm() {
  if [ -e "$LIB/pending-boot" ]; then
    confirm_boot
    return
  fi
  local sys
  sys=$(pending)
  [ -n "$sys" ] || die "nothing to confirm"
  systemctl stop osctl-revert.timer 2>/dev/null || true
  nix-env --profile "$PROFILE" --set "$sys"
  local rc=0
  activate "$sys" boot || rc=$?
  rm -f "$RUN/pending" "$RUN/deadline" "$RUN/previous" "$GCROOT" "$LIB/last-boot-revert"
  echo "generation $(current_gen)"
  if [ "$rc" != 0 ]; then
    echo "osctl-root: the change is kept, but the boot menu could not be updated (exit $rc): the next boot may still start the previous generation." >&2
    return "$rc"
  fi
}

cmd_revert() {
  local expired=${1:-}
  if [ -e "$LIB/pending-boot" ]; then
    revert_boot
    return
  fi
  local sys previous
  sys=$(pending)
  if [ -z "$sys" ]; then
    echo "nothing to revert"
    return 0
  fi
  previous=$(cat "$RUN/previous")
  [ "$expired" = --expired ] || systemctl stop osctl-revert.timer 2>/dev/null || true
  activate "$previous" test || true
  rm -f "$RUN/pending" "$RUN/deadline" "$RUN/previous" "$GCROOT"
  if [ "$expired" = --expired ]; then
    announce "osctl: the change on trial was not confirmed in time and has been reverted."
  else
    echo "reverted"
  fi
}

cmd_try_boot() {
  local sys=${1:-}
  check_system "$sys"
  nothing_pending || die "a change is already pending"
  bootctl is-installed --quiet 2>/dev/null || die "reboot trials need systemd-boot"
  local prev new prev_entry new_entry
  prev=$(current_gen)
  [ -n "$prev" ] || die "there is no current generation to fall back to"

  nix-env --profile "$PROFILE" --set "$sys"
  new=$(current_gen)
  activate "$sys" boot
  prev_entry=$(boot_entry "$prev")
  new_entry=$(boot_entry "$new")
  [ -n "$prev_entry" ] && [ -n "$new_entry" ] || {
    nix-env --profile "$PROFILE" --switch-generation "$prev"
    nix-env --profile "$PROFILE" --delete-generations "$new"
    activate "$(gen_path "$prev")" boot
    die "could not find the boot entries for generations $prev and $new"
  }

  # The old generation stays the default; the new one is booted exactly once. If it is
  # never confirmed, any later boot lands on the old one and boot-check cleans up.
  bootctl set-default "$prev_entry"
  bootctl set-oneshot "$new_entry"
  mkdir -p "$LIB"
  echo "$prev $new" > "$LIB/pending-boot"
  systemd-run --quiet --on-active=5s systemctl reboot
  echo "generation $new"
}

confirm_boot() {
  local prev new
  read -r prev new < "$LIB/pending-boot"
  [ "$(readlink -f /run/booted-system)" = "$(gen_path "$new")" ] ||
    die "generation $new is not the one running; reboot into it first, or run 'osctl revert'"
  bootctl set-default "" # back to loader.conf, whose default is the newest generation
  rm -f "$LIB/pending-boot" "$LIB/last-boot-revert"
  echo "generation $new"
}

revert_boot() {
  local prev new
  read -r prev new < "$LIB/pending-boot"
  nix-env --profile "$PROFILE" --switch-generation "$prev"
  nix-env --profile "$PROFILE" --delete-generations "$new"
  activate "$(gen_path "$prev")" boot || true
  bootctl set-default "" 2>/dev/null || true
  bootctl set-oneshot "" 2>/dev/null || true
  rm -f "$LIB/pending-boot"
  if [ "$(readlink -f /run/booted-system)" = "$(gen_path "$prev")" ]; then
    echo "reverted"
  else
    echo "reverted; reboot to go back to generation $prev"
  fi
}

cmd_boot_check() {
  [ -e "$LIB/pending-boot" ] || return 0
  local prev new
  read -r prev new < "$LIB/pending-boot"
  if [ "$(readlink -f /run/booted-system)" = "$(gen_path "$new")" ]; then
    logger -t osctl "booted generation $new on trial; waiting for osctl confirm"
  else
    logger -t osctl "generation $new was not confirmed before reboot; removing it"
    revert_boot
    echo "$new" > "$LIB/last-boot-revert"
  fi
}

cmd_rollback() {
  nothing_pending || die "a change is pending; use 'osctl revert'"
  nix-env --profile "$PROFILE" --rollback
  local rc=0
  activate "$PROFILE" switch || rc=$?
  echo "generation $(current_gen)"
  return "$rc"
}

action=${1:-}
shift || true
case "$action" in
  try) cmd_try "$@" ;;
  try-boot) cmd_try_boot "$@" ;;
  confirm) cmd_confirm ;;
  revert) cmd_revert "$@" ;;
  rollback) cmd_rollback ;;
  boot-check) cmd_boot_check ;;
  *) die "usage: osctl-root try SYSTEM SECONDS | try-boot SYSTEM | confirm | revert | rollback | boot-check" ;;
esac
