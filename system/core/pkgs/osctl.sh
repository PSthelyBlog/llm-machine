# osctl: the one way this system changes.
# The repo describes the system. osctl builds it, applies it on trial, and then keeps it
# (a new generation plus a git commit) or reverts it.

REPO=${LLM_MACHINE_REPO:-/etc/llm-machine}
HOST=${LLM_MACHINE_HOST:-$(uname -n)}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/osctl
PROFILE=/nix/var/nix/profiles/system
ROOT=(/run/wrappers/bin/sudo -n /run/current-system/sw/bin/osctl-root)
DEFAULT_TIMEOUT=120
TRIAL=refs/osctl/trial # the commit on trial, until it is kept or dropped

usage() {
  cat <<'EOF'
usage: osctl <command> [options]

  status [--brief]         what is running, what is on trial, what changed in the repo
  build                    build the system from the repo without applying it
  diff                     repo changes and package changes compared with the running system
  vm [--check]             boot the repo's system in a throwaway VM (--check: headless smoke test)
  try -m MESSAGE [-t SECONDS]
                           apply the repo's changes now on trial; reverted after SECONDS
                           (default 120) unless confirmed. MESSAGE says what changed
  try -m MESSAGE --reboot  for changes that need a reboot: boot them once; reverted unless confirmed
  confirm                  keep the change on trial: make it the boot default and commit it
  revert                   undo the change on trial now
  rollback [-m MESSAGE]    go back to the previous generation and make the repo match it
  log                      generations and the commits they were built from
EOF
}

die() {
  echo "osctl: $*" >&2
  exit 1
}

git_() { git -C "$REPO" "$@"; }
current_gen() { readlink "$PROFILE" 2>/dev/null | sed -E 's/^system-([0-9]+)-link$/\1/' || true; }
running() { readlink -f /run/current-system; }
built_from() { nixos-version --configuration-revision 2>/dev/null || true; }
trial_path() { cat /run/osctl/pending 2>/dev/null || true; }
trial_boot() { cat /var/lib/osctl/pending-boot 2>/dev/null || true; }
nothing_pending() { [ -z "$(trial_path)" ] && [ -z "$(trial_boot)" ]; }

check_repo() {
  [ -d "$REPO/.git" ] || die "$REPO is not a git repository"
  [ -d "$REPO/hosts/$HOST" ] || die "no host '$HOST' in $REPO/hosts"
  mkdir -p "$STATE"
}

# Build ATTR from the work tree, or from exactly COMMIT, so that the system records the
# commit it was built from. Flakes only see files git knows about, so stage everything.
build_attr() { # ATTR [COMMIT]
  local src=$REPO
  check_repo
  git_ add -A
  [ -z "${2:-}" ] || src="git+file://$REPO?rev=$2"
  nix build "$src#nixosConfigurations.$HOST.config.system.build.$1" \
    --out-link "$STATE/$1" --print-out-paths
}

# A commit of an exact tree on top of HEAD; later edits stay uncommitted in the work tree.
new_commit() {
  local tree=$1 msg=$2
  if [ -z "$(git_ config user.email || true)" ]; then
    git_ config user.name "${USER:-llm-machine}"
    git_ config user.email "${USER:-root}@$HOST"
  fi
  git_ commit-tree "$tree" -p HEAD -m "$msg"
}

commit_tree() {
  local tree=$1 msg=$2
  [ "$tree" != "$(git_ rev-parse 'HEAD^{tree}')" ] || return 0
  git_ update-ref HEAD "$(new_commit "$tree" "$msg")"
}

cmd_status() {
  local brief=${1:-} gen rev short
  gen=$(current_gen)
  rev=$(built_from)
  if short=$(git_ rev-parse -q --verify --short "$rev^{commit}" 2>/dev/null); then
    rev="commit $short"
  fi
  echo "Host $HOST, repo $REPO"
  echo "Running generation ${gen:-none} (built from ${rev:-an unknown revision})"

  local sys boot
  sys=$(trial_path)
  boot=$(trial_boot)
  if [ -n "$sys" ]; then
    local left=$(($(cat /run/osctl/deadline) - $(date +%s)))
    echo "ON TRIAL: a change is active and will be reverted in ${left}s. Keep it with 'osctl confirm', undo with 'osctl revert'."
  elif [ -n "$boot" ]; then
    local prev new
    read -r prev new <<<"$boot"
    if [ "$(readlink -f /run/booted-system)" = "$(readlink -f "$PROFILE-$new-link")" ]; then
      echo "ON TRIAL: booted generation $new once. Keep it with 'osctl confirm'; rebooting without confirming goes back to $prev."
    else
      echo "ON TRIAL: generation $new is waiting for its trial boot. Reboot to try it, or 'osctl revert' to drop it."
    fi
  fi
  if [ -f /var/lib/osctl/last-boot-revert ]; then
    echo "Note: generation $(cat /var/lib/osctl/last-boot-revert) was not confirmed after its trial boot and was removed."
  fi

  if [ -n "$(git_ status --porcelain 2>/dev/null || true)" ]; then
    echo "Repo changes not yet applied and kept:"
    git_ status --porcelain | sed 's/^/  /'
  else
    echo "Repo is clean."
  fi

  local failed
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ' || true)
  [ -z "$failed" ] || echo "Failed units: $failed"

  [ "$brief" = --brief ] && return 0
  echo
  df -h / /boot 2>/dev/null || true
}

cmd_build() {
  local out
  out=$(build_attr toplevel)
  echo "Built $out"
  [ "$out" != "$(running)" ] || echo "It is identical to the running system: there is nothing to apply."
}

cmd_diff() {
  local out
  out=$(build_attr toplevel)
  echo "== Repo changes since the last kept commit =="
  git_ --no-pager diff --cached --stat
  git_ --no-pager diff --cached
  echo
  echo "== Package changes, running system -> repo =="
  nvd diff /run/current-system "$out"
}

cmd_try() {
  local timeout=$DEFAULT_TIMEOUT reboot=no msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -m | --message)
        msg=${2:?}
        shift 2
        ;;
      -t | --timeout)
        timeout=${2:?}
        shift 2
        ;;
      --reboot)
        reboot=yes
        shift
        ;;
      *) die "try: unknown option $1" ;;
    esac
  done
  [ -n "$msg" ] || die "try: say in plain words what the change does, with -m \"...\""
  nothing_pending || die "a change is already on trial: 'osctl confirm' or 'osctl revert' it first"

  check_repo
  git_ add -A
  local tree commit out
  tree=$(git_ write-tree)
  if [ "$tree" = "$(git_ rev-parse -q --verify "$(built_from)^{tree}" 2>/dev/null || true)" ]; then
    echo "The running system was built from these very files: there is nothing to apply."
    return 0
  fi
  # Commit the change now, beside the branch rather than on it, and build from that
  # commit, so the system records which commit it is. 'osctl confirm' moves main onto it.
  commit=$(git_ rev-parse HEAD)
  [ "$tree" = "$(git_ rev-parse 'HEAD^{tree}')" ] || commit=$(new_commit "$tree" "$msg")
  git_ update-ref "$TRIAL" "$commit"
  out=$(build_attr toplevel "$commit")

  if [ "$reboot" = yes ]; then
    local gen
    gen=$("${ROOT[@]}" try-boot "$out")
    cat <<EOF
Rebooting in 5 seconds into $gen, once.
After the reboot, keep it with: osctl confirm
If it does not work, just reboot (or power off and on): the machine comes back on the previous generation.
EOF
    return 0
  fi

  local rc=0
  "${ROOT[@]}" try "$out" "$timeout" || rc=$?
  if [ "$rc" != 0 ] && [ "$rc" != 4 ]; then
    git_ update-ref -d "$TRIAL"
    die "the change could not be activated and was reverted"
  fi
  cat <<EOF
Applied on trial. It will be reverted automatically in ${timeout}s.
  keep it:  osctl confirm
  undo now: osctl revert
EOF
  return "$rc"
}

cmd_confirm() {
  [ $# -eq 0 ] || die "confirm takes no options: the change was described by 'osctl try -m'"
  ! nothing_pending || die "nothing is on trial"
  check_repo

  local rc=0
  "${ROOT[@]}" confirm >/dev/null || rc=$?
  local gen trial
  gen=$(current_gen)
  trial=$(git_ rev-parse -q --verify "$TRIAL" || git_ rev-parse HEAD)
  # main normally moves onto the very commit the system was built from. If main moved on
  # during the trial, the same files are committed on top of it instead.
  if [ "$(git_ rev-parse -q --verify "$trial^" || true)" = "$(git_ rev-parse HEAD)" ]; then
    git_ update-ref HEAD "$trial"
  else
    commit_tree "$(git_ rev-parse "$trial^{tree}")" "$(git_ log -1 --format=%B "$trial")"
  fi
  git_ update-ref -d "$TRIAL"
  git_ tag -f "gen-$gen" >/dev/null
  echo "Kept as generation $gen (commit $(git_ rev-parse --short HEAD))."
  return "$rc"
}

cmd_revert() {
  ! nothing_pending || {
    echo "Nothing is on trial."
    return 0
  }
  "${ROOT[@]}" revert
  git_ update-ref -d "$TRIAL"
  echo "The repo edits are still there, uncommitted: fix them and try again, or set them aside with 'git -C $REPO stash'."
}

cmd_rollback() {
  local msg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -m | --message)
        msg=${2:?}
        shift 2
        ;;
      *) die "rollback: unknown option $1" ;;
    esac
  done
  nothing_pending || die "a change is on trial: use 'osctl revert'"
  check_repo

  local from to rc=0
  from=$(current_gen)
  "${ROOT[@]}" rollback >/dev/null || rc=$?
  to=$(current_gen)
  [ "$from" != "$to" ] || die "there is no earlier generation to go back to"

  # Make the repo describe the running system again, as a new commit.
  if git_ rev-parse -q --verify "refs/tags/gen-$to" >/dev/null; then
    if [ -n "$(git_ status --porcelain)" ]; then
      git_ stash push --include-untracked -m "osctl: uncommitted edits before rolling back to generation $to" >/dev/null
      echo "Uncommitted repo edits were stashed (see 'git -C $REPO stash list')."
    fi
    git_ restore --source="gen-$to" --staged --worktree -- :/
    commit_tree "$(git_ write-tree)" "${msg:-Roll back to generation $to}"
  else
    echo "warning: no commit is tagged gen-$to, so the repo was left as it is." >&2
  fi
  echo "Rolled back from generation $from to $to."
  return "$rc"
}

cmd_log() {
  local cur link gen mark subject
  cur=$(current_gen)
  set -- "$PROFILE"-*-link
  [ -e "$1" ] || {
    echo "No generations yet."
    return 0
  }
  # Nix normalises mtimes to 1970, so date generations by when their link was created.
  for link in $(printf '%s\n' "$@" | sort -t- -k2 -n); do
    gen=${link#"$PROFILE"-}
    gen=${gen%-link}
    mark=" "
    [ "$gen" != "$cur" ] || mark="*"
    subject=$(git_ log -1 --format='%h %s' "gen-$gen" 2>/dev/null || echo "(no commit recorded)")
    printf '%s %4s  %s  %s\n' "$mark" "$gen" "$(date -d "@$(stat -c %Z "$link")" '+%Y-%m-%d %H:%M')" "$subject"
  done
}

cmd_vm() {
  local vm run disk
  vm=$(build_attr vm)
  run=$(echo "$vm"/bin/run-*-vm)
  disk="$STATE/vm-disk.qcow2"
  rm -f "$disk"
  if [ "${1:-}" != --check ]; then
    NIX_DISK_IMAGE=$disk exec "$run"
  fi

  # Headless smoke test: boot to multi-user, report what failed, shut down.
  local log="$STATE/vm-check.log" pid ok=no
  rm -f "$log"
  NIX_DISK_IMAGE=$disk QEMU_KERNEL_PARAMS="console=ttyS0" \
    QEMU_OPTS="-display none -serial file:$log -monitor none" "$run" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 300); do
    if grep -q 'Reached target.*Multi-User System' "$log" 2>/dev/null; then
      ok=yes
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  sleep 5 # let late units fail
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$disk"

  grep -aE 'Failed to start|FAILED|emergency mode|Kernel panic' "$log" | sed 's/^/  /' || true
  if [ "$ok" = yes ]; then
    echo "VM check passed: the system booted to multi-user (log: $log)."
  else
    die "VM check failed: the system did not reach multi-user within 5 minutes (log: $log)"
  fi
}

cmd=${1:-}
shift || true
case "$cmd" in
  status) cmd_status "$@" ;;
  build) cmd_build ;;
  diff) cmd_diff ;;
  vm) cmd_vm "$@" ;;
  try) cmd_try "$@" ;;
  confirm) cmd_confirm "$@" ;;
  revert) cmd_revert ;;
  rollback) cmd_rollback "$@" ;;
  log) cmd_log ;;
  "" | -h | --help | help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
