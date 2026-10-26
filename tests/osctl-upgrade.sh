# osctl upgrade, on throwaway repos: U plays llm-machine's own repo (with the shipped
# system in system/), M a machine's /etc/llm-machine as the installer creates it.
set -euo pipefail
T=$(mktemp -d)
U=$T/U M=$T/M
export LLM_MACHINE_REPO=$M LLM_MACHINE_HOST=h XDG_STATE_HOME=$T/state
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
fails() { if "$@"; then return 1; fi; }
check() { # DESCRIPTION COMMAND...
  "${@:2}" || {
    echo "FAILED: $1" >&2
    exit 1
  }
}

# Release R0, and a machine installed from it: the shipped system without hosts/ starts
# 'upstream', then the machine's own commits follow on main.
mkdir -p "$U/system/core" "$U/system/hosts/llm-vm"
printf 'line 1\nline 2\nline 3\n' > "$U/system/CLAUDE.md"
echo 'x = "v0";' > "$U/system/core/x.nix"
echo 'vm = 0;' > "$U/system/hosts/llm-vm/default.nix"
g "$U" init -q -b main && g "$U" add -A && g "$U" commit -q -m R0
mkdir -p "$M" && cp -r "$U/system/." "$M" && rm -rf "$M/hosts/llm-vm"
g "$M" init -q -b main && g "$M" add -A && g "$M" commit -q -m "as installed"
g "$M" branch upstream
mkdir -p "$M/hosts/h" "$M/features/hello"
echo 'host = "h";' > "$M/hosts/h/default.nix"
echo 'hello = 1;' > "$M/features/hello/default.nix"
sed -i 's/^line 1$/line 1, as this machine has it/' "$M/CLAUDE.md"
g "$M" add -A && g "$M" commit -q -m "this machine's changes"

# R1 changes core, another line of CLAUDE.md, and the development VM.
echo 'x = "v1";' > "$U/system/core/x.nix"
sed -i 's/^line 3$/line 3, as R1 has it/' "$U/system/CLAUDE.md"
echo 'vm = 1;' > "$U/system/hosts/llm-vm/default.nix"
g "$U" add -A && g "$U" commit -q -m R1
osctl upgrade "file://$U" main
check "core is updated" grep -q v1 "$M/core/x.nix"
check "the machine's edit is kept" grep -q 'as this machine has it' "$M/CLAUDE.md"
check "the release's edit is taken" grep -q 'as R1 has it' "$M/CLAUDE.md"
check "the machine's feature and host stay" test -f "$M/features/hello/default.nix" -a -f "$M/hosts/h/default.nix"
check "the development VM isn't brought in" test ! -e "$M/hosts/llm-vm"
check "a second upgrade waits for the first" fails osctl upgrade "file://$U" main

# Kept (osctl try records the merge; here a plain merge commit stands in for it).
g "$M" commit -q -m "Upgrade llm-machine"
out=$(osctl upgrade "file://$U" main)
check "a release already merged isn't merged again" grep -q 'already has the latest' <<<"$out"

# R2 changes the very line this machine changed.
sed -i 's/^line 1$/line 1, as R2 has it/' "$U/system/CLAUDE.md"
g "$U" add -A && g "$U" commit -q -m R2
check "the conflict is reported" fails osctl upgrade "file://$U" main
out=$(osctl build 2>&1 || true)
check "a build refuses conflict markers" grep -q 'conflict markers' <<<"$out"
g "$M" merge --abort
check "an aborted upgrade leaves the repo as it was" test -z "$(g "$M" status --porcelain)"
echo "osctl upgrade: all checks passed"
