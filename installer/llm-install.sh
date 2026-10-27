# llm-install: put llm-machine on this computer's disk. Everything after the first boot
# (drivers, language, desktop, apps) is Claude's job, so this only asks what it must:
# keyboard, network, disk, account.

SRC=/etc/llm-machine-source
MNT=/mnt
LOG=/tmp/llm-install.log
KEYFILE=/tmp/llm-machine-disk.key

title() {
  clear
  gum style --border rounded --padding "1 3" --margin "1 2" --border-foreground 173 \
    "llm-machine installer" "$@"
}
say() { gum style --margin "0 2" "$@"; }
# Drop keys pressed while nothing was asked, so they don't answer the next question.
drop_typed() { while read -r -s -t 0.1 -N 1 _; do :; done; }
fail() {
  gum style --margin "1 2" --foreground 1 "Installation failed: $*" \
    "Details are in $LOG. To start again: sudo llm-install"
  drop_typed # or run as a command in the shell after this
  exit 1
}

trap 'fail "unexpected error at line $LINENO"' ERR
[ "$(id -u)" = 0 ] || fail "run it as root: sudo llm-install"
[ -d /sys/firmware/efi ] || fail "this computer did not start in UEFI mode, which llm-machine needs. Switch the firmware to UEFI and start again."

# --- Keyboard ----------------------------------------------------------------------

# Each is an xkb layout, and a variant if needed: what desktops use, and what the console
# follows (console.useXkbConfig). kbd's own console maps aren't used: some are wrong, and
# its "fr" types { } @ instead of é è à.
declare -A KEYBOARDS=(
  ["English (US)"]=us ["English (UK)"]=gb ["French"]=fr ["German"]=de ["Spanish"]=es
  ["Italian"]=it ["Portuguese"]=pt ["Brazilian (ABNT2)"]=br ["Belgian"]=be
  ["Swiss French"]="ch fr" ["Swiss German"]=ch ["Canadian French"]=ca ["Dutch"]=nl
  ["Swedish"]=se ["Norwegian"]=no ["Danish"]=dk ["Finnish"]="fi" ["Polish"]=pl
  ["Russian"]="us,ru" ["Japanese"]=jp
  ["English (US, Dvorak)"]="us dvorak" ["English (US, Colemak)"]="us colemak"
)

title "This puts llm-machine on this computer. It takes a few minutes; after a" \
  "restart, Claude takes over and sets up the rest with you."
say "Which keyboard layout do you use?"
keyboard=$(printf '%s\n' "${!KEYBOARDS[@]}" | sort | gum choose --height 12 --selected "English (US)")
read -r xkb_layout xkb_variant <<<"${KEYBOARDS[$keyboard]}"
xkb_options=terminate:ctrl_alt_bksp # the NixOS default
# With two layouts, Alt+Shift switches between them.
[[ "$xkb_layout" != *,* ]] || xkb_options="grp:alt_shift_toggle,$xkb_options"
# Build the console map the way NixOS builds it from the same settings
# (nixos/modules/config/console.nix), so a disk passphrase typed now is typed the same
# way at boot.
ckbcomp -model pc104 -layout "$xkb_layout" -variant "$xkb_variant" -option "$xkb_options" \
  > /tmp/keymap.map
loadkeys -q /tmp/keymap.map

# --- Network -----------------------------------------------------------------------

online() { curl -fs -o /dev/null -m 5 https://cache.nixos.org/nix-cache-info; }
until online; do
  title "No internet connection"
  say "The installer downloads the system, and Claude needs the internet." \
    "Plug in a cable, or choose a Wi-Fi network in the next screen and then Quit."
  if gum confirm "Open the network settings?" --affirmative "Open" --negative "Retry"; then
    nmtui connect || true
  fi
done

# --- Disk --------------------------------------------------------------------------

stable_path() { # prefer a /dev/disk/by-id name: /dev/sdX can change between boots
  local link
  for link in /dev/disk/by-id/*; do
    case "$link" in *-part[0-9]* | */wwn-* | */nvme-eui.*) continue ;; esac
    if [ "$(readlink -f "$link")" = "$1" ]; then
      echo "$link"
      return
    fi
  done
  echo "$1"
}

iso_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /iso 2>/dev/null || echo none)" 2>/dev/null || true)
mapfile -t disks < <(lsblk -dnpo NAME,TYPE,RO,SIZE,MODEL | awk -v skip="/dev/$iso_disk" \
  '$2 == "disk" && $3 == 0 && $1 != skip && $1 !~ /zram|loop/ { $2 = $3 = ""; print }')
[ "${#disks[@]}" -gt 0 ] || fail "no disk to install to was found"

title "Which disk should llm-machine use?"
say "Everything on it will be erased."
disk=$(printf '%s\n' "${disks[@]}" | gum choose | awk '{ print $1 }')
[ -n "$disk" ] || fail "no disk was chosen; nothing was changed"

title "Erase $disk?"
say "$(lsblk -po NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$disk")" "" \
  "Everything on this disk will be lost. Type ERASE to continue."
if [ "$(gum input --placeholder ERASE)" != ERASE ]; then
  say "Nothing was changed."
  sleep 2
  exec "$0"
fi

layout=btrfs
if gum confirm "Encrypt the disk? Recommended for laptops: you type a passphrase every time the computer starts."; then
  layout=btrfs-luks
  while true; do
    p1=$(gum input --password --placeholder "Disk passphrase")
    p2=$(gum input --password --placeholder "The same passphrase again")
    [ -n "$p1" ] && [ "$p1" = "$p2" ] && break
    say "The passphrases were empty or didn't match. Try again."
  done
  (umask 077 && printf '%s' "$p1" > "$KEYFILE")
fi

# --- Account -----------------------------------------------------------------------

title "Your account"
fullname=$(gum input --placeholder "Your name" | tr -d '"\\$')
username=$(echo "$fullname" | awk '{ print tolower($1) }' | tr -cd 'a-z0-9_-')
while true; do
  username=$(gum input --value "$username" --placeholder "Username (lowercase, no spaces)")
  [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [[ ! "$username" =~ ^(root|nixos|dev)$ ]] && break
  say "Use lowercase letters, digits, - or _, starting with a letter."
done
while true; do
  password=$(gum input --password --placeholder "Password")
  again=$(gum input --password --placeholder "The same password again")
  [ -n "$password" ] && [ "$password" = "$again" ] && break
  say "The passwords were empty or didn't match. Try again."
done
hostname=llm-machine
while true; do
  hostname=$(gum input --value "$hostname" --placeholder "Name of this computer")
  [[ "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] && [ "$hostname" != llm-vm ] && break
  say "Use letters, digits and -, starting with a letter or digit."
done

# --- Confirm -----------------------------------------------------------------------

title "Ready to install"
say "Disk:      $disk, erased$([ "$layout" = btrfs ] || echo ", encrypted")" \
  "Keyboard:  $keyboard" \
  "Account:   $fullname ($username)" \
  "Computer:  $hostname"
gum confirm "Install now?" || exec "$0"

# --- Install -----------------------------------------------------------------------

# Nothing is asked again until the end, so keys pressed meanwhile aren't shown, and the
# end drops them. Typing shows again once the installer exits, even after a failure.
tty_state=$(stty -g 2> /dev/null || true)
trap '[ -z "$tty_state" ] || stty "$tty_state" 2> /dev/null || true' EXIT
stty -echo 2> /dev/null || true

# The screen says what is happening; what the tools print goes to the log.
step() {
  echo "== $1" >> "$LOG"
  say "$1"
}
# A step that runs COMMAND, with a spinner while it does.
spin() {
  local title=$1 pid
  shift
  echo "== $title" >> "$LOG"
  "$@" >> "$LOG" 2>&1 &
  pid=$!
  gum spin --spinner line --title "$title" -- tail --pid "$pid" -s 0.2 -f /dev/null
  wait "$pid" || return
  say "$title"
}

repo=$MNT/etc/llm-machine
hostdir=$repo/hosts/$hostname

sed "s|@DEVICE@|$(stable_path "$disk")|" "$SRC/core/disko/$layout.nix" > /tmp/disk.nix
spin "Partitioning and formatting $disk..." \
  disko --mode destroy,format,mount --yes-wipe-all-disks /tmp/disk.nix || fail "formatting the disk"
[ ! -e "$KEYFILE" ] || shred -u "$KEYFILE"

step "Writing the system description to /etc/llm-machine..."
mkdir -p "$repo"
cp -r "$SRC/." "$repo" # $SRC is a symlink into the store: copy what it points to
chmod -R u+w "$repo"
rm -rf "$repo/hosts/llm-vm"
# The system as shipped, without any machine, is the start of the 'upstream' branch:
# 'osctl upgrade' adds later releases there and merges them into main.
git -C "$repo" init -q -b main
git -C "$repo" config user.name "$fullname"
git -C "$repo" config user.email "$username@$hostname"
git -C "$repo" add -A
git -C "$repo" commit -q -m "llm-machine, as installed"
git -C "$repo" branch upstream
mkdir -p "$hostdir"
cp /tmp/disk.nix "$hostdir/disk.nix"
nixos-generate-config --root "$MNT" --no-filesystems --show-hardware-config \
  > "$hostdir/hardware-configuration.nix" 2>> "$LOG"
keyboard_config="services.xserver.xkb.layout = \"$xkb_layout\";"
[ -z "$xkb_variant" ] || keyboard_config+="
  services.xserver.xkb.variant = \"$xkb_variant\";"
[ "$xkb_options" = terminate:ctrl_alt_bksp ] || keyboard_config+="
  services.xserver.xkb.options = \"$xkb_options\";"
keyboard_config+="
  console.useXkbConfig = true; # the console follows the keyboard layout above"
[ "$layout" = btrfs ] || keyboard_config+="
  console.earlySetup = true; # the disk passphrase is typed with this layout"
cat > "$hostdir/default.nix" <<EOF
# This machine. The installer wrote this file; Claude looks after it.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disk.nix
  ];

  llm-machine.user = "$username";
  users.users."$username".description = "$fullname";

  $keyboard_config

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # The NixOS release this machine was installed with. Don't change it.
  system.stateVersion = "$(nixos-version | cut -d. -f1,2)";
}
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "Install $hostname"

step "Installing. This downloads the system and can take a while..."
# Nix writes to the screen, where it shows one progress line instead of a line for each
# download. (Its json-log-path record would be hundreds of MB of RAM here.)
nixos-install --root "$MNT" --flake "$repo#$hostname" --no-root-passwd --no-channel-copy \
  >> "$LOG" || fail "installing the system; the message above says why"

printf '%s:%s\n' "$username" "$password" | nixos-enter --root "$MNT" -c chpasswd >> "$LOG" 2>&1 ||
  fail "setting the password"

# Bring the Wi-Fi networks along, so the first boot is online.
connections=(/etc/NetworkManager/system-connections/*)
if [ -e "${connections[0]}" ]; then
  install -d -m 700 "$MNT/etc/NetworkManager/system-connections"
  install -m 600 /etc/NetworkManager/system-connections/* "$MNT/etc/NetworkManager/system-connections/"
fi

gen=$(readlink "$MNT/nix/var/nix/profiles/system" | sed -E 's/^system-([0-9]+)-link$/\1/')
git -C "$repo" tag "gen-$gen"
chown -R 1000:100 "$repo"

title "llm-machine is installed."
say "Remove the installation USB stick, then press Enter to restart." \
  "After the restart, Claude will greet you."
# An Enter pressed during the install would restart right away, with the stick still in.
drop_typed
read -r _
umount -R "$MNT" || true
reboot
