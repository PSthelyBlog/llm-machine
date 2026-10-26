# llm-machine (development repo)

An operating system that Claude Code builds and maintains: NixOS underneath, Claude as
the administrator, `osctl` as the only way the system changes.

`system/` is what ships. On an installed machine it becomes `/etc/llm-machine`, a flake
the running system is built from. `system/CLAUDE.md` and `system/.claude/` are
instructions for Claude **running on that machine**. They don't apply to development
sessions here, so don't follow them (for example, sudo is fine on the dev host).

## Layout

- `system/core/`: base modules (osctl, tty1 session, Claude Code policy, repo seeding)
  and the scripts in `system/core/pkgs/`.
- `system/features/`: empty on purpose; Claude fills it in on each machine.
- `system/hosts/llm-vm/`: the development VM. The installer drops it from installed systems.
- `installer/`: the ISO and `llm-install`.
- `dev/`: QEMU runners and `qmp.py` for screenshots and typing into a VM.

## Commands

- `nix build .#iso`: installer ISO in `result/iso/`.
- `nix run .#vm -- [--reset] [--headless]`: boot `llm-vm` from the build.
  `ssh -p 2222 dev@localhost`, password `dev`.
- `nix run .#iso-vm -- [--reset] [--disk-only] [--headless]`: UEFI install onto
  `.vm/install.qcow2`.
- `nix run .#check-gates`: after nixpkgs brings a new Claude Code, check that it still
  asks before `osctl try`/`confirm`/`rollback` in auto mode. Uses the host's signed-in
  Claude (four small Sonnet requests); the NixOS tests can't cover this.
- `python3 dev/qmp.py .vm/qmp-vm.sock screenshot /tmp/s.png`, `... type 'text\n'`, `... paste` (the host clipboard), `... key ctrl-alt-f2`.
  `type` assumes a US layout in the VM; once its keyboard is French, set `QMP_KEYMAP=fr`.
- `dev/test-install.sh [--encrypt] [--french]`: an unattended install from the ISO onto
  `.vm/install.qcow2`, then the first boot, with screenshots in `.vm/`.
- Signing in inside a VM: both VMs forward port 8765, so the phone sign-in page from the
  QR code (`zbarimg -q --raw` on a screenshot) opens on the host at
  `http://localhost:8765/<token>`; the code itself shows the VM's address, 10.0.2.15.

## Notes

- Flakes only see git-tracked files: `git add` new files before building.
- `system/flake.lock` pins nixpkgs for everything; the root flake reuses
  `machine.inputs.nixpkgs`. Update with `nix flake update --flake ./system`, then
  `nix flake update machine`.
- Shell scripts are built with `writeShellApplication`, so shellcheck runs on every build.
