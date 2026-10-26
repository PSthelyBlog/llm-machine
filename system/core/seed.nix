{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.llm-machine;
in
{
  options.llm-machine.seed.enable = lib.mkEnableOption ''
    creating the system repo from the source of this build on first boot. For VMs and
    disk images; on a normal install the installer creates the repo
  '';

  config = lib.mkIf cfg.seed.enable {
    systemd.services.llm-machine-seed = {
      description = "Create the llm-machine system repo";
      wantedBy = [ "multi-user.target" ];
      before = [ "systemd-user-sessions.service" ];
      unitConfig.ConditionPathExists = "!${cfg.repo}";
      path = [ pkgs.git ];
      serviceConfig.Type = "oneshot";
      script = ''
        cp -r ${inputs.self} ${cfg.repo}
        chmod -R u+w ${cfg.repo}
        cd ${cfg.repo}
        git init -q -b main
        git config user.name ${lib.escapeShellArg cfg.user}
        git config user.email ${lib.escapeShellArg "${cfg.user}@${config.networking.hostName}"}
        git add -A
        git commit -q -m "Initial system"
        chown -R ${lib.escapeShellArg cfg.user}:users ${cfg.repo}
      '';
    };
  };
}
