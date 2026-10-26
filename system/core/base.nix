{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.llm-machine;
in
{
  system.nixos.distroName = "llm-machine";
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) cfg.allowUnfree;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  # Generations are the rollback history. Keep a month of them; the boot menu shows the last 20.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 20;

  networking.networkmanager.enable = true;
  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;
  zramSwap.enable = true;

  # Lets prebuilt Linux binaries (that expect /lib64/ld-linux.so) run.
  programs.nix-ld.enable = true;

  users.users.${cfg.user} = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "input"
    ];
  };

  # Tools Claude uses to look at the machine.
  environment.systemPackages = with pkgs; [
    curl
    dmidecode
    fd
    file
    git
    htop
    inxi
    jq
    lshw
    nvd
    pciutils
    ripgrep
    tree
    usbutils
    wget
  ];
}
