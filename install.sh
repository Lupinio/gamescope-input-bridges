#!/usr/bin/env bash
# Install the gamescope input bridges for the current user.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bindir="$HOME/.local/bin"
unitdir="$HOME/.config/systemd/user"
units=(gamescope-pen-touch gamescope-tap-click gamescope-win-taste)

if ! python3 -c "import evdev" 2>/dev/null; then
    echo "python-evdev is missing. Install it first, e.g.:" >&2
    echo "  sudo pacman -S python-evdev     # Arch, CachyOS" >&2
    echo "  sudo apt install python3-evdev  # Debian, Ubuntu" >&2
    exit 1
fi

echo "==> scripts to $bindir"
mkdir -p "$bindir"
install -m755 "$here"/bin/* "$bindir/"

echo "==> user units to $unitdir"
mkdir -p "$unitdir"
install -m644 "$here"/systemd/*.service "$unitdir/"

echo "==> udev rules (needs sudo)"
# These grant the seat user an ACL on exactly the two devices involved, which is
# why the services do not need the user to be in the input group.
sudo install -m644 "$here"/udev/*.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=input

echo "==> enabling units"
systemctl --user daemon-reload
for u in "${units[@]}"; do
    systemctl --user enable "$u.service"
done

cat <<'EOF'

Done. The units are tied to gamescope-session.target, so they start with
Gaming Mode rather than right now. Switch to Gaming Mode and check:

  systemctl --user status gamescope-pen-touch gamescope-tap-click gamescope-win-taste

On hardware other than a GPD Win Max 2, adjust the touchpad name in
/etc/udev/rules.d/72-gpd-touchpad-uaccess.rules and KEYBOARD_NAME in
~/.local/bin/gamescope-win-taste. Use evtest to find the right names.
EOF
