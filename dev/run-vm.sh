# Boot the development machine (system/hosts/llm-vm) straight from the build.
# usage: nix run .#vm -- [--reset] [--headless]
# The disk image, QMP socket and serial log live in ./.vm; ssh -p 2222 dev@localhost (password dev).

dir=${LLM_VM_DIR:-$PWD/.vm}
display=()
for arg in "$@"; do
  case "$arg" in
    --reset) rm -f "$dir/llm-vm.qcow2" ;;
    --headless) display=(-display none) ;;
    *)
      echo "usage: nix run .#vm -- [--reset] [--headless]" >&2
      exit 1
      ;;
  esac
done
mkdir -p "$dir"
rm -f "$dir/qmp-vm.sock"

export NIX_DISK_IMAGE=$dir/llm-vm.qcow2
export QEMU_OPTS="${display[*]} -qmp unix:$dir/qmp-vm.sock,server=on,wait=off -serial file:$dir/serial-vm.log"
echo "llm-vm: ssh -p 2222 dev@localhost (password dev), QMP $dir/qmp-vm.sock, serial log $dir/serial-vm.log"
exec @vm@/bin/run-llm-vm-vm
