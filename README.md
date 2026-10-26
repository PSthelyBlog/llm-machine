# llm-machine

An operating system that Claude Code sets up and maintains.

```
firmware → systemd-boot (every generation listed: rollback without Claude)
  → NixOS → autologin on tty1 → tmux: F1 Claude │ F2 shell │ F3 network │ F4 sign-in QR
       ├─ offline?          → network settings (nmtui)
       ├─ not signed in?    → claude auth login: a QR code opens a page on the phone that
       │                      hands the sign-in code back, so nothing has to be typed
       ├─ first boot?       → claude "/setup" (Claude Code's own first-start screens are
       │                      answered already): hardware survey, a few questions, then
       │                      drivers, language, desktop and apps, each applied on trial
       └─ afterwards        → ask Claude for anything; it edits the system repo
```

The system is a git repo, `/etc/llm-machine`, holding a NixOS flake. Claude changes the
machine by editing that repo and running `osctl`:

| command | what it does |
| --- | --- |
| `osctl build` / `diff` | build the repo, show repo and package changes |
| `osctl vm --check` | boot the change in a throwaway VM first |
| `osctl try -m …` | commit the change beside `main` and activate it; **reverted automatically after 120 s** unless confirmed |
| `osctl try -m … --reboot` | the same, booting the change once; **the next boot falls back** unless confirmed |
| `osctl confirm` | keep it: new boot default, and its commit joins `main`, tagged `gen-N` |
| `osctl revert` / `rollback` | undo the trial / go back a generation, with the repo matching |
| `osctl upgrade [URL]` | merge the latest llm-machine release (this repo's `system/`) into the machine's repo, keeping its own changes; then try it like any change |

Claude runs as the user. Only `osctl-root`, which activates built systems and nothing
else, runs as root. A machine-wide Claude Code policy (`/etc/claude-code/managed-settings.json`),
which Claude can't edit, starts Claude in auto mode, blocks `sudo`, disk tools and bypass
mode, and makes `osctl try`, `confirm`, `rollback` and `upgrade`, and edits to `core/`, always ask
the user, in every mode.

During sign-in, the tty1 session serves the phone page on TCP port 8765 at a secret
address, and accepts only a code for the sign-in on screen; nothing listens there
otherwise. `llm-machine.session.phoneSignIn = false` turns it off.

## Try it

Needs Nix with flakes, and KVM.

```sh
nix run .#vm                 # boot the dev machine straight from the build
nix run .#iso-vm             # or the real path: UEFI install from the ISO onto a blank disk,
nix run .#iso-vm -- --disk-only   # then boot the installed system
nix build .#iso              # the installer image, in result/iso/
nix flake check              # osctl and session tests in VMs
nix run .#check-gates        # with your signed-in Claude: osctl still asks in auto mode
```

The installer asks only for keyboard, network, disk (optionally encrypted) and account.
Claude Code itself is fetched from Anthropic at install time and isn't part of the ISO.

## Layout

- `system/`: what ships; becomes `/etc/llm-machine`. `core/` is the base, `features/` is
  filled in by Claude on each machine, `hosts/<name>/` is per machine, and `CLAUDE.md` plus
  `.claude/skills/` are Claude's instructions on the machine.
- `installer/`: the ISO and `llm-install`.
- `dev/`: QEMU runners and `qmp.py` (screenshots and typing for automated tests).

## Releases

Installed machines upgrade (`osctl upgrade`) from the `stable` branch of this repository.
Development happens on `main`; `stable` only moves forward to commits that passed
`nix flake check` and a test install.

## License

MIT, see [LICENSE](LICENSE). Claude Code is not part of this repository or the ISO: each
machine downloads it from Anthropic, under Anthropic's terms, when it is built.
