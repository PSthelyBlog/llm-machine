# The trial mechanics of osctl-root: a change on trial is reverted when its timer runs
# out, kept when confirmed, and undone by rollback. And osctl upgrade's merging of
# releases. Run with: nix build .#checks.x86_64-linux.osctl
{ pkgs, machine }:
let
  upgradeTest = pkgs.writeShellScript "osctl-upgrade-test" (builtins.readFile ./osctl-upgrade.sh);
in
pkgs.testers.runNixOSTest {
  name = "osctl";

  node.specialArgs = { inherit (machine) inputs; };
  # core sets nixpkgs.config (allowUnfreePredicate), so the node builds its own pkgs.
  node.pkgsReadOnly = false;

  nodes.machine = {
    imports = [ machine.nixosModules.core ];
    llm-machine.user = "dev";
    llm-machine.session.enable = false;
    virtualisation.memorySize = 2048;
    # The test VM has no disk to install a bootloader on; generations still work.
    boot.loader.grub.enable = false;

    # A second system to switch to: the same machine with one extra file in /etc.
    specialisation.feature.configuration.environment.etc."osctl-test".text = "on";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    base = machine.succeed("readlink -f /run/current-system").strip()
    feature = machine.succeed("readlink -f /run/current-system/specialisation/feature").strip()
    machine.succeed(f"nix-env -p /nix/var/nix/profiles/system --set {base}")

    def running():
        # What 'osctl status' says is running.
        return machine.succeed("su - dev -c 'osctl status --brief' | grep '^Running'").strip()

    def kept():
        return machine.succeed("readlink /nix/var/nix/profiles/system").split("-")[1]

    with subtest("a change on trial is reverted when the timer runs out"):
        machine.succeed(f"osctl-root try {feature} 10")
        machine.succeed("test -e /etc/osctl-test")
        machine.succeed("test -e /run/osctl/pending")
        machine.wait_until_fails("test -e /run/osctl/pending", timeout=60)
        machine.fail("test -e /etc/osctl-test")
        assert machine.succeed("readlink -f /run/current-system").strip() == base

    with subtest("an explicit revert undoes the change and disarms the timer"):
        machine.succeed(f"osctl-root try {feature} 300")
        machine.succeed("osctl-root revert")
        machine.fail("test -e /etc/osctl-test")
        machine.fail("systemctl is-active osctl-revert.timer")

    with subtest("only one change can be on trial"):
        machine.succeed(f"osctl-root try {feature} 300")
        machine.fail(f"osctl-root try {feature} 300")

    with subtest("status doesn't call a change on trial the kept generation"):
        assert running().startswith("Running the change on trial"), running()
        assert running().endswith(f"the last kept generation is {kept()}."), running()

    with subtest("a confirmed change stays and becomes the new generation"):
        machine.succeed("osctl-root confirm")
        machine.fail("systemctl is-active osctl-revert.timer")
        machine.sleep(5)
        machine.succeed("test -e /etc/osctl-test")
        assert machine.succeed("readlink -f /nix/var/nix/profiles/system").strip() == feature
        assert running().startswith(f"Running generation {kept()} "), running()

    with subtest("rollback returns to the previous generation"):
        machine.succeed("osctl-root rollback")
        machine.fail("test -e /etc/osctl-test")
        assert machine.succeed("readlink -f /nix/var/nix/profiles/system").strip() == base

    with subtest("only NixOS systems are accepted"):
        machine.fail("osctl-root try /tmp 60")
        machine.fail(f"osctl-root try {feature} 3")

    with subtest("the primary user may run osctl-root, and nothing else, without a password"):
        machine.succeed("su dev -c 'sudo -n /run/current-system/sw/bin/osctl-root revert'")
        machine.fail("su dev -c 'sudo -n true'")

    with subtest("an upgrade merges a release and keeps the machine's own changes"):
        machine.succeed("su - dev -c ${upgradeTest}")
  '';
}
