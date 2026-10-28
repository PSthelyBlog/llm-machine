# Big builds on a small machine: Nix doesn't grow with the number of packages it builds; a
# build that needs more memory than the machine has finishes, slowly, while the user's
# session keeps the memory it uses; a build that would fill the swap too is stopped, and
# nothing else is. Run with:
# nix build .#checks.x86_64-linux.memory
{ pkgs, machine }:
let
  build = pkgs.writeCBin "memory-build" (builtins.readFile ./memory-build.c);
  session = pkgs.writeCBin "memory-session" (builtins.readFile ./memory-session.c);

  # Made on the machine, which has no internet to fetch anything from.
  builds = pkgs.writeText "memory-test.nix" ''
    let
      system = "x86_64-linux";
      bash = "''${builtins.storePath "${pkgs.bash}"}/bin/bash";
    in
    {
      # A build that needs MB of memory; 0 for more and more, until it is stopped.
      big = mb: derivation {
        name = "big-''${toString mb}";
        inherit system;
        builder = "''${builtins.storePath "${build}"}/bin/memory-build";
        args = [ (toString mb) "200" "1" ];
      };
      # A build of N small packages, like the dependencies of an npm project.
      many = n: derivation {
        name = "many-''${toString n}";
        inherit system;
        builder = bash;
        args = [ "-c" "echo > $out" ];
        packages = builtins.genList (i: derivation {
          name = "small-''${toString i}";
          inherit system;
          builder = bash;
          args = [ "-c" "echo ''${toString i} > $out" ];
        }) n;
      };
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "memory";

  node.specialArgs = { inherit (machine) inputs; };
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [ machine.nixosModules.core ];
    llm-machine.user = "dev";
    llm-machine.session.enable = false;
    boot.loader.grub.enable = false;
    virtualisation.memorySize = 1024;
    virtualisation.cores = 2;
    # A btrfs root, like an installed machine's, so it gets the swap file too.
    virtualisation.useDefaultFilesystems = false;
    virtualisation.rootDevice = "/dev/vda";
    virtualisation.fileSystems."/" = {
      device = "/dev/vda";
      fsType = "btrfs";
      autoFormat = true;
    };
    virtualisation.diskSize = 8192;

    environment.systemPackages = [ session ];
    environment.etc."memory-test.nix".source = builds;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("memory runs over into zram, then into a swap file"):
        machine.wait_for_unit("dev-zram0.swap")
        machine.wait_for_unit("var-lib-swapfile.swap")

    # The user's session, standing in: 200 MB it uses every few seconds.
    machine.succeed(
        "systemd-run --unit=session --slice=user.slice -p User=dev"
        " -p StandardOutput=file:/tmp/session memory-session 200"
    )
    machine.wait_until_succeeds("test -s /tmp/session")
    seen = 0

    def build(what):
        return machine.execute(
            f"su - dev -c 'nix-build --no-out-link -E \"(import /etc/memory-test.nix).{what}\"' 2>&1"
        )

    def check_session():
        # It kept its memory, and never waited long to use it.
        global seen
        waits = [int(w) for w in machine.succeed("cat /tmp/session").split()]
        swapped = int(machine.succeed("cat /sys/fs/cgroup/user.slice/session.service/memory.swap.peak"))
        print(f"session: waited {waits[seen:]} ms; {swapped >> 20} MB swapped out at most")
        assert len(waits) > seen, "the session stopped"
        assert max(waits[seen:]) < 1000, waits[seen:]
        assert swapped < 8 << 20, swapped
        seen = len(waits)

    with subtest("Nix doesn't hold on to memory for each package it builds"):
        # Nix 2.34 did, about 0.75 MB a package: a few hundred took it past 300 MB.
        status, out = build("many 400")
        assert status == 0, out
        peak = int(machine.succeed("cat /sys/fs/cgroup/system.slice/nix-daemon.service/memory.peak"))
        print(f"nix: {peak >> 20} MB at most")
        assert peak < 150 << 20, peak

    with subtest("a build that needs more memory than the machine has finishes"):
        status, out = build("big 1536")
        assert status == 0, out
        swapped = int(machine.succeed("cat /sys/fs/cgroup/system.slice/nix-daemon.service/memory.swap.peak"))
        print(f"build: {swapped >> 20} MB swapped out at most")
        assert swapped > 512 << 20, swapped
        check_session()

    with subtest("a build that would fill the swap too is stopped"):
        status, out = build("big 0")
        assert status != 0, out
        machine.succeed("journalctl -u systemd-oomd | grep 'Marked /system.slice/nix-daemon.service for killing'")
        machine.wait_until_fails("pgrep -x memory-build")
        check_session()
        # The next build starts Nix again.
        status, out = build("big 1")
        assert status == 0, out
  '';
}
