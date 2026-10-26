{ pkgs, ... }:
{
  # Fetched from downloads.claude.ai when the system is built, not shipped in the ISO.
  llm-machine.allowUnfree = [ "claude-code" ];
  environment.systemPackages = [ pkgs.claude-code ];

  # Machine-wide policy that no user or project setting can loosen. These rules catch the
  # commands Claude would normally write; the real gate is that root changes only go
  # through osctl, which asks the user before anything is applied.
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    permissions = {
      disableBypassPermissionsMode = "disable";
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
