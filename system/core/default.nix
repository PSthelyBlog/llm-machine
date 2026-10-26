# The llm-machine core: what every machine gets. Machine-specific settings live in
# hosts/<hostname>/, and everything the user asks for lives in features/.
{ lib, inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./base.nix
    ./claude.nix
    ./osctl.nix
    ./session.nix
    ./seed.nix
  ];

  options.llm-machine = {
    user = lib.mkOption {
      type = lib.types.str;
      description = "The primary user of this machine. Claude Code runs as this user.";
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "/etc/llm-machine";
      description = "The git repository this system is built from.";
    };

    allowUnfree = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "nvidia-x11"
        "steam"
      ];
      description = "Names of the unfree packages allowed on this machine. Any module can add to it.";
    };
  };
}
