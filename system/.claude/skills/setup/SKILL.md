---
name: setup
description: First-boot setup of this computer. Surveys the hardware, asks the user a few questions, then configures drivers, language, desktop and apps, each step on trial. Starts automatically on first boot; /setup resumes it.
---

# Set up this computer

llm-machine has just been installed: a console, networking and you. Turn it into the
computer the user wants with as few questions as possible, applying each stage on trial.

## 0. Find out where things stand

Run `osctl status` and `git -C /etc/llm-machine log --oneline`, and check whether
`hosts/<hostname>/hardware.md` exists. Then pick up where things stopped. Don't redo
stages that were confirmed.

- **A change is on trial:** ask the user whether it works, naming what they should see
  (for example "the new desktop came up and you can hear sound"). Confirm or revert it,
  then carry on with the next stage.
- **`hardware.md` exists:** the survey is done. Look at `features/` and the git log to see
  which stages are confirmed.

## 1. Welcome (first time only)

In a few lines: you'll look at the hardware, ask a handful of questions, and then set
things up. Every change is tried first and can be undone, and most of the time is spent on
downloads. Don't lecture.

## 2. Survey the hardware

These commands run without prompting: `lscpu`, `lspci -nnk`, `lsusb`, `lsblk -f`,
`inxi -Fxxz`, `fwupdmgr get-devices`, `nmcli device`. Also read
`/sys/class/dmi/id/{sys_vendor,product_name}` and `/sys/class/power_supply/*/type` (a
`Battery` means it's a laptop).

Decide:

- **Graphics.** Intel or AMD: `hardware.graphics.enable = true;`. NVIDIA: the proprietary
  driver needs the user's agreement (unfree). Use `services.xserver.videoDrivers =
  [ "nvidia" ];` and `hardware.nvidia.open = true;` for Turing (RTX 20xx/GTX 16xx) and
  newer, and add `nvidia-x11` and `nvidia-settings` to `llm-machine.allowUnfree`. Hybrid
  laptops also need `hardware.nvidia.prime` offload with the bus IDs from `lspci`.
- **Bluetooth:** `hardware.bluetooth.enable = true;` if there is a controller.
- **Laptop:** `services.power-profiles-daemon.enable = true;` and `services.upower.enable = true;`.
- **Fingerprint reader:** `services.fprintd.enable = true;`, only for a supported device.
- **Firmware:** mention updates that `fwupdmgr get-updates` reports; don't apply them.

Write `hosts/<hostname>/hardware.md`: what the machine is, the parts that matter, and what
you decided for each, in plain words.

## 3. Ask

One `AskUserQuestion` round, recommending defaults from the survey:

1. **Language and region:** locale and timezone. Guess from the keyboard layout chosen
   in the installer, `services.xserver.xkb.layout` in `hosts/<hostname>/default.nix`.
2. **Desktop:** GNOME (recommended for newcomers), KDE Plasma (looks like Windows),
   Hyprland (tiling, keyboard-driven), or none (console only).
3. **Use** (multi-select): web and email, office documents, programming, gaming, photos
   and media, printing.
4. **Automatic login:** recommend keeping it only if the disk is encrypted (check for
   `type = "luks"` in `hosts/<hostname>/disk.nix`).

Ask more only if an answer leaves something important open.

## 4. Apply in stages, each on trial

**Stage A: language, region and hardware (no reboot).** Put `time.timeZone` and
`i18n.defaultLocale` in `hosts/<hostname>/default.nix`. The keyboard is already there,
from the installer: change `services.xserver.xkb.layout` only if the user asks, and leave
the console following it (`console.useXkbConfig = true`) rather than setting
`console.keyMap`, because some of kbd's own console maps are wrong (its `fr` types
`{ } @` instead of `é è à`). Put drivers, Bluetooth and power in `features/hardware/`,
and printing (`services.printing.enable`, `services.avahi`) in `features/printing/` if the
user asked for it. Then `osctl build`, `osctl diff`, `osctl try -m "..."`. Have the user
check something concrete (`date` shows the right time), then `osctl confirm`.

**Stage B: desktop and apps (reboot).** Skip this stage if the user chose no desktop.

- `features/desktop/`: display manager, desktop, PipeWire audio
  (`services.pipewire = { enable = true; alsa.enable = true; pulse.enable = true; };`),
  fonts, a terminal. Also set `llm-machine.session.enable = false;`, since the desktop
  takes over tty1, and set `llm-machine.session.terminal` so you come back in a terminal
  after the reboot.
  - GNOME: `services.displayManager.gdm.enable = true;`,
    `services.desktopManager.gnome.enable = true;`,
    `llm-machine.session.terminal = "kgx --";`, and
    `environment.gnome.excludePackages = [ pkgs.gnome-tour ];` so GNOME's welcome tour
    doesn't cover your terminal on the first login.
  - KDE Plasma: `services.displayManager.sddm = { enable = true; wayland.enable = true; };`,
    `services.desktopManager.plasma6.enable = true;`,
    `llm-machine.session.terminal = "konsole -e";`
  - Hyprland: `programs.hyprland = { enable = true; withUWSM = true; };` (UWSM runs the
    XDG autostart entry that brings you back), a login manager such as
    `services.greetd` with tuigreet, and `kitty`; `llm-machine.session.terminal = "kitty";`.
  - Automatic login, if the user kept it: `services.displayManager.autoLogin = { enable = true; user = "<user>"; };`.
  - Check each option exists before using it:
    `nix eval /etc/llm-machine#nixosConfigurations.$(uname -n).options.<option>.description`.
- `features/apps/`: what the answers in step 3 call for (Firefox for web, LibreOffice
  for office, Steam with `programs.steam.enable` and the unfree names it needs for
  gaming, and so on). Keep it short; the user can ask for more later.

`osctl build` and `osctl diff`. Then tell the user: the computer restarts into the new
desktop; once they log in, you'll open in a terminal and check with them; if anything goes
wrong, restarting the computer brings it back exactly as it is now. Then
`osctl try -m "..." --reboot`. Your session ends there. When you're back (step 0), check
with the user and `osctl confirm`.

## 5. Finish

Run `mkdir -p ~/.local/state/llm-machine && touch ~/.local/state/llm-machine/setup-done`,
then give a short summary: what was set up, how to ask for changes (talk to you; `os` in a
terminal starts you), and how to undo things (ask you, or pick an older generation in the
boot menu).
