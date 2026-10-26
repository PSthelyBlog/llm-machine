# llm-machine

An operating system that Claude Code sets up and maintains.

```
firmware → systemd-boot (every generation listed: rollback without Claude)
  → NixOS → autologin on tty1 → tmux: F1 Claude │ F2 shell │ F3 network │ F4 sign-in QR
       ├─ offline?          → network settings (nmtui)
       ├─ not signed in?    → Claude's login; the sign-in link pops up as a QR code
       ├─ first boot?       → claude "/setup": hardware survey, a few questions, then
       │                      drivers, language, desktop and apps, each applied on trial
       └─ afterwards        → ask Claude for anything; it edits the system repo
```

The system is a git repo, `/etc/llm-machine`, holding a NixOS flake. Claude changes the
machine by editing that repo and running `osctl`:

| command | what it does |
| --- | --- |
| `osctl build` / `diff` | build the repo, show repo and package changes |
| `osctl vm --check` | boot the change in a throwaway VM first |
| `osctl try` | activate now; **reverted automatically after 120 s** unless confirmed |
| `osctl try --reboot` | boot the change once; **the next boot falls back** unless confirmed |
| `osctl confirm -m …` | keep it: new boot default, plus a git commit tagged `gen-N` |
| `osctl revert` / `rollback` | undo the trial / go back a generation, with the repo matching |

Claude runs as the user. Only `osctl-root`, which activates built systems and nothing
else, runs as root. A machine-wide Claude Code policy (`/etc/claude-code/managed-settings.json`)
blocks `sudo`, disk tools and bypass mode, and project settings make `osctl try` and
`confirm` ask before running.

## Try it

Needs Nix with flakes, and KVM.

```sh
nix run .#vm                 # boot the dev machine straight from the build
nix run .#iso-vm             # or the real path: UEFI install from the ISO onto a blank disk,
nix run .#iso-vm -- --disk-only   # then boot the installed system
nix build .#iso              # the installer image, in result/iso/
```

The installer asks only for keyboard, network, disk (optionally encrypted) and account.
Claude Code itself is fetched from Anthropic at install time and isn't part of the ISO.

## Layout

- `system/`: what ships; becomes `/etc/llm-machine`. `core/` is the base, `features/` is
  filled in by Claude on each machine, `hosts/<name>/` is per machine, and `CLAUDE.md` plus
  `.claude/skills/` are Claude's instructions on the machine.
- `installer/`: the ISO and `llm-install`.
- `dev/`: QEMU runners and `qmp.py` (screenshots and typing for automated tests).
