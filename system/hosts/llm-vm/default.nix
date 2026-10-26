# A development machine that boots straight from the build in QEMU (nix run .#vm in the
# llm-machine repo). The installer leaves it out of installed systems.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  # QEMU boots the kernel directly; generations still work, there is just no boot menu.
  boot.loader.grub.enable = false;

  llm-machine.user = "dev";
  llm-machine.seed.enable = true;

  users.users.dev.initialPassword = "dev";
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  virtualisation = {
    memorySize = 4096;
    cores = 4;
    diskSize = 20480;
    # osctl builds new systems inside the VM: keep what it downloads on disk, not in RAM.
    writableStoreUseTmpfs = false;
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
      # The phone sign-in page (llm-login-relay); its QR code shows the VM's own address.
      {
        from = "host";
        host.port = 8765;
        guest.port = 8765;
      }
    ];
  };

  system.stateVersion = "26.05";
}
