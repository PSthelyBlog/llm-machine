{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.llm-machine;

  osctl-root = pkgs.writeShellApplication {
    name = "osctl-root";
    runtimeInputs = [
      config.nix.package
      config.systemd.package
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.util-linux
    ];
    text = builtins.readFile ./pkgs/osctl-root.sh;
  };

  osctl = pkgs.writeShellApplication {
    name = "osctl";
    runtimeInputs = [
      config.nix.package
      config.systemd.package
      pkgs.coreutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nvd
    ];
    text = builtins.readFile ./pkgs/osctl.sh;
  };
in
{
  environment.systemPackages = [
    osctl
    osctl-root
  ];
  environment.sessionVariables.LLM_MACHINE_REPO = cfg.repo;

  # osctl-root never takes a command to run, only a built NixOS system to activate or a
  # generation to go back to, so the primary user may call it without a password.
  security.sudo.extraRules = [
    {
      users = [ cfg.user ];
      commands = [
        {
          command = "/run/current-system/sw/bin/osctl-root";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # A generation booted on trial (osctl try --reboot) that was never confirmed is removed
  # on the next boot, which by then is back on the previous generation.
  systemd.services.osctl-boot-check = {
    description = "osctl: discard an unconfirmed reboot trial";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe osctl-root} boot-check";
    };
  };
}
