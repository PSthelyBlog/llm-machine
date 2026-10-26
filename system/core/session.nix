{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.llm-machine;

  script =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text =
        builtins.replaceStrings
          [ "@tmuxConf@" "@terminal@" ]
          [ "${./pkgs/tmux.conf}" (toString cfg.session.terminal) ]
          (builtins.readFile ./pkgs/${name}.sh);
    };

  front-door = script "llm-front-door" [
    pkgs.curl
    pkgs.networkmanager
    pkgs.tmux
    login-qr
  ];
  login-qr = script "llm-login-qr" [
    pkgs.gawk
    pkgs.qrencode
    pkgs.tmux
    pkgs.ncurses
  ];
  session = script "llm-session" [
    pkgs.tmux
    front-door
  ];
  resume = script "llm-resume" [ front-door ];

  # Claude, from anywhere, working on this system.
  os = pkgs.writeShellApplication {
    name = "os";
    text = ''
      cd "''${LLM_MACHINE_REPO:-${cfg.repo}}"
      exec claude "$@"
    '';
  };
in
{
  options.llm-machine.session = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the llm-machine session when the primary user logs in on tty1: Claude in the
        first tmux window, a shell in the second.
      '';
    };
    autologin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Log the primary user in on tty1 automatically, once per boot.";
    };
    terminal = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "konsole -e";
      description = ''
        How to open a terminal running a command in the graphical session. When set, a
        terminal with Claude opens at login while setup is unfinished or a trial reboot is
        waiting to be confirmed.
      '';
    };
  };

  config = lib.mkMerge [
    {
      environment.systemPackages = [
        os
        pkgs.tmux
      ];
    }

    (lib.mkIf cfg.session.enable {
      environment.systemPackages = [
        session
        login-qr
      ];
      services.getty = lib.mkIf cfg.session.autologin {
        autologinUser = cfg.user;
        autologinOnce = true;
      };
      environment.loginShellInit = ''
        if [ "$(tty)" = /dev/tty1 ] && [ "$USER" = ${lib.escapeShellArg cfg.user} ] && [ -z "''${TMUX:-}" ]; then
          exec llm-session
        fi
      '';
    })

    (lib.mkIf (cfg.session.terminal != null) {
      environment.etc."xdg/autostart/llm-machine-resume.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=llm-machine
        Comment=Bring Claude back while setup is unfinished or a change awaits confirmation
        Exec=${lib.getExe resume}
        NoDisplay=true
      '';
    })
  ];
}
