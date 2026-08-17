# gamescope-input-bridges

Three small userspace bridges that give a handheld gaming PC its stylus,
tap-to-click and menu key back inside gamescope's Gaming Mode.

Built for a **GPD Win Max 2 (G1619-04)** running CachyOS with
gamescope 3.16.24, but nothing here is GPD-specific except two device names.

| Bridge | Missing capability | Approach |
|---|---|---|
| `gamescope-pen-touch` | gamescope implements no Wayland tablet protocol, so the built-in stylus is dead in Gaming Mode | read the pen with evdev, replay tip-down as single-finger touch on a virtual touchscreen |
| `gamescope-tap-click` | gamescope never configures libinput, so tap-to-click stays off no matter what the desktop is set to | watch the touchpad, replay short motionless touches as button presses on a virtual mouse |
| `gamescope-win-taste` | the Windows key does nothing, while Steam registers its menu hotkeys as `Shift+Tab` | emit `Shift+Tab` on a virtual keyboard when Meta is released alone |

Each one runs as a user unit tied to `gamescope-session.target`, so the
desktop session keeps its own native behaviour and nothing fires twice.

---

## Why these are needed

The interesting part of this project was not writing the bridges — it was
establishing *why* each capability is missing, because in all three cases the
obvious explanation was wrong.

### gamescope ships no tablet protocol

Not "the pen is misconfigured" — the protocol is absent from the binary:

```console
$ strings -a /usr/bin/gamescope | grep -c zwp_tablet
0
```

A zero alone proves nothing, so the counter-check matters. Other unstable
protocols are present, which means the binary is not stripped of these strings:

```console
$ strings -a /usr/bin/gamescope | grep -oE 'zwp_[a-z_]+' | sort -u | head -5
zwp_confined_pointer_v
zwp_linux_buffer_params_v
zwp_linux_dmabuf_feedback_v
zwp_linux_dmabuf_v
zwp_locked_pointer_v
```

There is no `zwp_tablet_manager_v2`, so no client in the session can ever
receive a stylus event. Notably gamescope *does* import
`libinput_device_tablet_pad_*` — it can see a tablet's button pad through
libinput — but it has no protocol to forward the stylus itself to clients.

Touch, by contrast, gamescope handles natively. Hence the bridge direction:
pen → touch.

### gamescope never configures libinput

The touchpad case looked like a libinput default that a quirk could flip. It
isn't. gamescope links libinput and imports 127 of its symbols:

```console
$ nm -D --undefined-only /usr/bin/gamescope | grep -c libinput
127
```

But it imports **no device-configuration symbols at all** — not tap, not
scrolling, not acceleration:

```console
$ nm -D --undefined-only /usr/bin/gamescope | grep -c 'libinput_device_config_'
0
```

While libinput itself exports the whole family:

```console
$ nm -D --defined-only /usr/lib/libinput.so.10 | grep -c 'libinput_device_config_tap_'
13
```

So the functions exist and gamescope simply never calls them. No amount of
configuration on the libinput or desktop side can turn tapping on, because
nothing in the session ever asks for it. That is what makes a replay bridge
the right fix rather than a workaround.

### Steam's hotkeys are registered with gamescope, not with X

Steam announces its shortcuts to the compositor at session start:

```
binding: (GuideKeyboardHotkey) -> Adding new trigger [Tab + Shift_L]
binding: (QAMKeyboardHotkey)   -> Adding new trigger [Tab + Control_L + Shift_L]
```

Because gamescope evaluates these itself, a virtual keyboard reaches them from
anywhere, including inside a running game. An earlier attempt through
`xbindkeys` could not work in principle: Steam lives on XWayland `:0` and games
on `:1`, so the binding never saw the key at all.

---

## What was non-obvious

The findings that cost the most time, kept as comments in the source:

- **Multitouch frames must be judged on `SYN_REPORT`, not per event.** X and Y
  arrive as separate events; measuring drift on each one compares a fresh X
  against a stale Y and reads as a jump. That alone silently ate every tap
  whose predecessor landed elsewhere on the pad.
- **`INPUT_PROP_DIRECT` is the whole trick** for the pen bridge. Without it udev
  tags the virtual device `ID_INPUT_TOUCHPAD` instead of `ID_INPUT_TOUCHSCREEN`,
  and gamescope looks for the latter.
- **A virtual mouse needs `REL_X`/`REL_Y` it never writes.** Without those axes
  udev tags the device as a plain key device and libinput ignores its buttons.
- **A 20 ms click can be dropped entirely.** Steam's UI is CEF and samples per
  frame, so the press has to be held ~60 ms to reliably land between frames.
- **Measured, not assumed:** libinput's tap timeout is 180 ms, but real lazy
  taps on this pad reach 270 ms. The timeout was widened to 300 ms and the
  movement check carries the actual rejection work instead.
- **Stale coordinates poison the next touch.** The position dict has to be
  cleared on `BTN_TOUCH` down, or the previous touch's last point becomes this
  touch's origin and the drift check misfires.

---

## Install

Requires `python-evdev`.

```sh
git clone https://github.com/Lupinio/gamescope-input-bridges
cd gamescope-input-bridges
./install.sh
```

The installer copies the scripts to `~/.local/bin`, installs the user units,
and installs two udev rules (needs `sudo`) that grant the seat user an ACL on
exactly the two input devices involved — rather than adding the user to the
`input` group, which would hand over every input device on the machine.

Adjust the device names in `udev/72-gpd-touchpad-uaccess.rules` and
`bin/gamescope-win-taste` for other hardware; `evtest` will tell you what
yours are called.

Verify after a session restart:

```sh
systemctl --user status gamescope-pen-touch gamescope-tap-click gamescope-win-taste
```

`gamescope-tap-click --dry-run` logs its decisions without emitting clicks,
which is the fastest way to tune `TAP_SECONDS` and `MOVE_MM` for a different
touchpad.

---

## Limitations

- The pen bridge deliberately drops pressure, hover and the barrel button.
  Touch has no concept of them, and this is a bridge, not a tablet driver.
- Only single-finger touch is bridged; the pen is one contact by definition.
- The Meta key is not grabbed exclusively, so `Super+F` and friends still reach
  gamescope. A bare Meta press does nothing on its own in either gamescope or
  Steam, so nothing is lost by only acting on release.
- Tested on one machine and one gamescope version. The binary checks above are
  the first thing to re-run if a future gamescope gains a tablet protocol —
  at which point `gamescope-pen-touch` should be deleted, not maintained.

## License

MIT
