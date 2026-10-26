{
  description = "llm-machine development: the installer ISO and test VMs";

  # system/ is what gets installed on a machine (and becomes /etc/llm-machine there).
  inputs.machine.url = "path:./system";

  outputs =
    { machine, ... }:
    let
      nixpkgs = machine.inputs.nixpkgs;
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      installer = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit machine; };
        modules = [ ./installer/iso.nix ];
      };

      iso = installer.config.system.build.isoImage;
      vm = machine.nixosConfigurations.llm-vm.config.system.build.vm;

      app = name: description: replacements: {
        type = "app";
        meta = { inherit description; };
        program = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [ pkgs.qemu_kvm ];
            text = builtins.replaceStrings (builtins.attrNames replacements) (builtins.attrValues replacements) (
              builtins.readFile ./dev/${name}.sh
            );
          }
        );
      };
    in
    {
      nixosConfigurations = {
        inherit installer;
        inherit (machine.nixosConfigurations) llm-vm;
      };

      packages.x86_64-linux = {
        inherit iso vm;
        default = iso;
      };

      apps.x86_64-linux = {
        vm = app "run-vm" "Boot the development machine straight from the build" { "@vm@" = "${vm}"; };
        iso-vm = app "run-iso" "Install from the ISO onto a blank UEFI virtual disk" {
          "@iso@" = "${iso}";
          "@ovmf@" = "${pkgs.OVMF.fd}";
        };
      };

      checks.x86_64-linux.osctl = import ./tests/osctl.nix { inherit pkgs machine; };

      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.nixfmt
          pkgs.shellcheck
        ];
      };
    };
}
