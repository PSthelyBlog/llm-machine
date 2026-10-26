# The installer ISO: a minimal NixOS live system that runs llm-install on tty1.
{
  lib,
  pkgs,
  modulesPath,
  machine,
  ...
}:
let
  llm-install = pkgs.writeShellApplication {
    name = "llm-install";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gawk
      git
      gnused
      gum
      kbd
      machine.inputs.disko.packages.${pkgs.stdenv.hostPlatform.system}.disko
      networkmanager
      nixos-install-tools
      util-linux
    ];
    text = builtins.readFile ./llm-install.sh;
  };
in
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.nixos.distroName = "llm-machine";
  image.baseName = lib.mkForce "llm-machine-installer";
  isoImage.volumeID = "LLM_MACHINE";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # The system the installer copies to /mnt/etc/llm-machine, and the flake inputs it
  # needs, so evaluating it doesn't download them again.
  environment.etc."llm-machine-source".source = machine.outPath;
  system.extraDependencies = [
    machine.inputs.nixpkgs.outPath
    machine.inputs.disko.outPath
  ];

  environment.systemPackages = [ llm-install ];

  environment.loginShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ "$USER" = nixos ]; then
      sudo llm-install || true
    fi
  '';
  services.getty.helpLine = lib.mkForce ''
    The llm-machine installer runs on tty1. To start it again: sudo llm-install
  '';
}
