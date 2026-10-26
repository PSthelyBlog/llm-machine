{ config, pkgs, ... }:
let
  # Path rules in managed settings need an absolute path, written with a leading //.
  repo = "/" + config.llm-machine.repo;
in
{
  # Fetched from downloads.claude.ai when the system is built, not shipped in the ISO.
  llm-machine.allowUnfree = [ "claude-code" ];
  environment.systemPackages = [ pkgs.claude-code ];

  # Machine-wide policy that no user or project setting can loosen, and that Claude can't
  # edit: it lives outside the repo and only changes through osctl.
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    permissions = {
      # In auto mode a classifier approves routine actions instead of asking the user, who
      # often can't judge a raw command anyway. The ask rules below still prompt in every
      # mode: they are the decisions that belong to the user.
      defaultMode = "auto";
      disableBypassPermissionsMode = "disable";
      ask = [
        "Bash(osctl try *)"
        "Bash(osctl confirm *)"
        "Bash(osctl rollback *)"
        "Bash(osctl upgrade *)"
        "Edit(${repo}/core/**)"
        "Edit(${repo}/flake.nix)"
        "Edit(${repo}/CLAUDE.md)"
        "Edit(${repo}/.claude/settings.json)"
      ];
      # These catch the commands Claude would normally write. They aren't a sandbox: the
      # real gate is that root changes only go through osctl, behind the ask rules above.
      deny = [
        "Bash(sudo *)"
        "Bash(su *)"
        "Bash(doas *)"
        "Bash(pkexec *)"
        "Bash(nixos-rebuild *)"
        "Bash(nixos-install *)"
        "Bash(osctl-root *)"
        "Bash(dd *)"
        "Bash(mkfs *)"
        "Bash(wipefs *)"
        "Bash(sgdisk *)"
        "Bash(sfdisk *)"
        "Bash(fdisk *)"
        "Bash(parted *)"
        "Bash(cryptsetup *)"
        "Bash(disko *)"
        "Bash(nix-collect-garbage *)"
      ];
    };
  };
}
