# Install llm-machine from the ISO onto a blank virtual disk, booting with UEFI like a
# real computer. Once installed, --disk-only boots the installed system.
# usage: nix run .#iso-vm -- [--reset] [--disk-only] [--headless]

dir=${LLM_VM_DIR:-$PWD/.vm}
disk=$dir/install.qcow2
vars=$dir/install-OVMF_VARS.fd
cdrom=yes
display=()
for arg in "$@"; do
  case "$arg" in
    --reset) rm -f "$disk" "$vars" ;;
    --disk-only) cdrom=no ;;
    --headless) display=(-display none) ;;
    *)
      echo "usage: nix run .#iso-vm -- [--reset] [--disk-only] [--headless]" >&2
      exit 1
      ;;
  esac
done
mkdir -p "$dir"
rm -f "$dir/qmp-install.sock"
[ -f "$disk" ] || qemu-img create -q -f qcow2 "$disk" 40G
[ -f "$vars" ] || install -m 644 @ovmf@/FV/OVMF_VARS.fd "$vars"

args=(
  -name llm-machine-install
  -enable-kvm -machine q35 -cpu host -smp 4 -m 4096
  -drive "if=pflash,format=raw,readonly=on,file=@ovmf@/FV/OVMF_CODE.fd"
  -drive "if=pflash,format=raw,file=$vars"
  -drive "file=$disk,if=none,id=disk0,format=qcow2"
  -device "virtio-blk-pci,drive=disk0,serial=llm-disk0,bootindex=1"
  -nic "user,model=virtio-net-pci,hostfwd=tcp::8765-:8765" # the phone sign-in page
  -qmp "unix:$dir/qmp-install.sock,server=on,wait=off"
  -serial "file:$dir/serial-install.log"
  "${display[@]}"
)
if [ "$cdrom" = yes ]; then
  args+=(
    -drive "file=$(echo @iso@/iso/*.iso),if=none,id=cd0,media=cdrom,readonly=on"
    -device "ide-cd,drive=cd0,bootindex=0"
    -no-reboot # the installer's reboot ends the VM, instead of booting the ISO again
  )
fi
echo "llm-machine install VM: QMP $dir/qmp-install.sock, serial log $dir/serial-install.log"
qemu-system-x86_64 "${args[@]}"
[ "$cdrom" = no ] || echo "To boot the installed system: nix run .#iso-vm -- --disk-only"
