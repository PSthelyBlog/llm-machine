---
name: feature
description: Add, change or remove something on this computer, such as software, drivers, services or system settings. Use whenever the user asks for a change to the system ("install X", "make Y do Z", "get rid of X").
---

# Change the system

1. **Understand the request.** If it's ambiguous, ask one question. Check that nothing is
   on trial (`osctl status`), and look in `features/` for a feature this belongs in.
2. **Find the NixOS way.** Prefer a module option over a bare package:
   - Does an option exist? `nix eval /etc/llm-machine#nixosConfigurations.$(uname -n).options.services.<name>.enable.description`
   - Reference: `man configuration.nix`, searchable with `/`.
   - Packages: `nix eval nixpkgs#<name>.meta.description`, or `nix search nixpkgs <words>`
     (slow the first time).
3. **Write the feature.** Use `features/<name>/default.nix`, named for what the user
   wanted, plus `features/<name>/README.md` with what it does, why the user asked for it,
   and how to use it.

   ```nix
   # features/printing/default.nix
   { ... }:
   {
     services.printing.enable = true;
     services.avahi = {
       enable = true;
       nssmdns4 = true;
     };
   }
   ```

   To remove a feature, delete its directory. To change one, edit it and its README.
4. **Build and check:** `osctl build` until it passes, then `osctl diff`. Tell the user in
   a sentence or two what will change, including download size if it's large and any
   unfree software.
5. **Apply on trial.** Use `osctl try -m "<what changed, in plain words>"`, adding
   `--reboot` for boot, kernel, driver and desktop changes (see CLAUDE.md). Tell the user
   what to check and that the change undoes itself if they don't confirm.
6. **Keep or undo.** If it works, `osctl confirm`. If not, `osctl revert`, fix it, and
   try again. If it can't be done, explain why.

User-level settings in the home directory (`~/.config/...`) are not part of the repo. Change
them only when asked, and tell the user which file you changed.
