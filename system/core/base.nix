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
  # Nix 2.34 holds memory for each derivation it builds until the whole build is over: a
  # build of a thousand small packages took the daemon past 2 GB and froze a 4 GB machine.
  # 2.35 doesn't. This does nothing once nixpkgs' own Nix is 2.35 or newer.
  nix.package = lib.mkIf (lib.versionOlder pkgs.nix.version "2.35") (
    lib.mkDefault pkgs.nixVersions.nix_2_35
  );

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

  # A big build may need more memory than the machine has. It is allowed, and slows down
  # instead of freezing the machine: when memory runs short, the kernel takes it from the
  # builds (they swap, to disk past zram) and leaves the user's session, Claude and the
  # desktop, the memory they use. A build is stopped only when the swap is nearly full too.
  zramSwap.enable = true;
  # Not mkDefault: disko's own swapDevices, even empty, would replace it.
  swapDevices = lib.mkIf (config.fileSystems."/".fsType or null == "btrfs") [
    {
      device = "/var/lib/swapfile";
      size = 4096; # MiB
    }
  ];
  # MemoryMin, not MemoryLow: with the kernel's MGLRU page reclaim (on by default), MemoryLow
  # only makes the kernel take the session's memory last, and it still takes all of it.
  systemd.slices.user.sliceConfig.MemoryMin = "30%";
  systemd.slices.system.sliceConfig.ManagedOOMSwap = "kill";
  nix.daemonCPUSchedPolicy = "batch";
  nix.daemonIOSchedClass = "idle";

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
