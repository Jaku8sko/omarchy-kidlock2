# kidlock — classroom keyboard lock for Omarchy OS

A small, transparent keyboard-lock plugin for **Omarchy OS (Wayland + Hyprland)**,
for educational/classroom use. A teacher/administrator can lock the keyboard so a
student keeps typing normally in the assigned app/webpage, while shortcut,
system, window-management and browser-escape combos are swallowed before they
reach any application. The mouse keeps working, and a bar icon (mouse-click)
toggles the lock.

> **Honesty first:** this is a *shortcut-blocking aid*, not a secure kiosk. See
> [Security limitations](#security-limitations).

## Supported environment

| Component | Status |
|---|---|
| Omarchy OS 4.x (Hyprland 0.56, Lua config API) | ✅ primary target (this repo was built and tested here) |
| Hyprland with the Lua `hl.*` API (`define_submap`, `dsp.no_op`) | ✅ required |
| Omarchy Quickshell bar (centre widget) | ✅ native widget included |
| Waybar (`custom/kidlock` module) | ✅ snippet included (for older Omarchy / stock Hyprland) |
| X11 / other compositors (GNOME, KDE, Sway, …) | ❌ not supported |

Dependencies: `hyprctl`, `bash`, `python3` (stdlib only, for the lua generator),
`systemctl --user` (optional, autostart). No root, no extra packages.

## How the keyboard filtering works

No keylogger-style grabbing, no evdev, no root. The whole trick is one
Hyprland feature: **submaps**.

1. `~/.config/hypr/kidlock.lua` (generated) calls
   `hl.define_submap("kidlock", "reset", …)` and registers ~700 binds inside it,
   every one mapped to the **`no_op` dispatcher**. A bound combo is *consumed
   by the compositor* — the focused client never receives it.
2. `kidlock lock` runs `hyprctl eval 'hl.dispatch(hl.dsp.submap("kidlock"))'`.
   While in that submap:
   - every `Ctrl/Alt/Super(+Shift)+<key>` combo is swallowed (Ctrl+W, Ctrl+T,
     Alt+F4, Alt+Tab, Super+…, Ctrl+Alt+T, … — policy-based, not a hard list);
   - bare `Esc / Tab / arrows / Home / End / PgUp / PgDn / F1–F12 / Print / …`
     are swallowed (tunable via `BLOCK_*` flags);
   - **all default Hyprland binds go inactive**, because they live in the
     `reset` submap (workspace switching, window moving/closing, launcher…);
   - anything **not bound** — letters, digits, space, enter, backspace, delete,
     punctuation, **Shift for uppercase/symbols**, and the **mouse** — flows
     through exactly as before.
3. `kidlock unlock` dispatches `submap("reset")`: everything is back to normal.

There is **no daemon**. Enforcement lives in the compositor config; the CLI
only flips submaps and records state. A crashed bar/widget/terminal therefore
cannot wedge input — and `kidlock unlock` from *any* shell always recovers.

## Installation

```bash
cd kidlock
./install.sh                 # Quickshell bar (Omarchy 4 default)
./install.sh --with-waybar   # also drop Waybar files into ~/.config/waybar
./install.sh --no-autostart  # skip enabling the login service
```

What it does: installs `~/.local/bin/kidlock`, creates
`~/.config/kidlock/kidlock.conf` (kept on re-install), generates
`~/.config/hypr/kidlock.lua`, appends `require("hypr.kidlock")` to
`~/.config/hypr/bindings.lua`, installs the Quickshell widget and places it in
the **bar centre**, installs+enables the user service, reloads Hyprland, runs
`kidlock doctor`.

The installer preflights `python3` (hard requirement) and `hyprctl` /
Hyprland version (warn-only outside a 0.56+ session).

## Manual installation (Hyprland with the Lua API, non-Omarchy)

If `~/.config/hypr/bindings.lua` does not exist (stock Hyprland), do the
equivalent of what `install.sh` automates:

```bash
mkdir -p ~/.local/bin ~/.config/kidlock ~/.config/hypr
cp bin/kidlock ~/.local/bin/kidlock
cp lib/generate_lua.py ~/.local/bin/kidlock-generate-lua
chmod +x ~/.local/bin/kidlock ~/.local/bin/kidlock-generate-lua
cp config/kidlock.conf ~/.config/kidlock/kidlock.conf   # keep existing on re-install
kidlock apply-config                                     # generates ~/.config/hypr/kidlock.lua
```

then load the generated module from your Hyprland Lua entrypoint (whichever
file your setup `require`s at startup):

```lua
require("hypr.kidlock")
```

and `hyprctl reload && kidlock doctor`. Requires the `hl.*` Lua API
(`define_submap`, `dsp.no_op`) — hard requirement; `kidlock doctor` reports
`FAIL: kidlock submap unknown` on compositors without it.

## Configuration (`~/.config/kidlock/kidlock.conf`)

| Key | Default | Meaning |
|---|---|---|
| `KIDLOCK_ENABLED` | `true` | master switch for auto-lock at login |
| `KIDLOCK_INITIAL_STATE` | `UNLOCKED` | `LOCKED`/`UNLOCKED` applied at login |
| `KIDLOCK_USER` | *(empty)* | set to the student login to refuse other users |
| `BLOCK_ESC / BLOCK_TAB / BLOCK_ARROWS / BLOCK_NAV / BLOCK_FKEYS / BLOCK_SYS` | `true` | which bare-key groups to swallow |

After editing `BLOCK_*`: `kidlock apply-config && hyprctl reload`.

## Starting / stopping

```bash
systemctl --user start kidlock.service    # apply initial state now
systemctl --user stop kidlock.service     # unlock (ExecStop unlocks)
systemctl --user enable kidlock.service   # autostart at login
systemctl --user disable kidlock.service  # no autostart
```

## Enable / disable the lock

- **Mouse (normal path):** click the 🔓/🔒 icon in the centre of the bar.
  Click while `UNLOCKED` → locks; click while `LOCKED` → unlocks.
- **Terminal:** `kidlock lock` / `kidlock unlock` / `kidlock toggle`, `kidlock status`.

## Waybar configuration (Waybar systems)

1. Add `"custom/kidlock"` to `modules-center` in `~/.config/waybar/config`
   (full object in `waybar/waybar-module.jsonc`).
2. Append `waybar/kidlock.css` to `~/.config/waybar/style.css`.
3. Restart waybar. Green `🔓 UNLOCKED` ⇄ blinking-red `🔒 LOCKED`; click toggles.

## Hyprland integration

Generated `~/.config/hypr/kidlock.lua` + one line in `~/.config/hypr/bindings.lua`:
`require("hypr.kidlock")`. Regenerate any time with `kidlock apply-config`;
verify with `kidlock doctor` and `hyprctl -j binds | grep kidlock`.

## Student-session scope

`hyprctl` talks to **this user's** Hyprland instance
(`HYPRLAND_INSTANCE_SIGNATURE`), so the lock physically cannot affect another
user's session, the admin account, or other seats. `kidlock` refuses to run as
root and outside a Hyprland session; optionally pin `KIDLOCK_USER="student"` to
make it refuse for anyone else. No root privileges are used anywhere.

## Emergency / admin recovery (read this before relying on the lock)

Ordered by convenience; **all are independent of the locked keyboard path**:

1. **Any shell, any way you can get one:** `kidlock unlock`
   (terminal emulator via mouse, SSH from another machine, …).
2. **Virtual terminal (always works):** press `Ctrl+Alt+F3`, log in as the
   student (or admin → `su - student`), run `kidlock unlock`, then `Ctrl+Alt+F1/F2`
   back. VT-switching is handled by the kernel, *not* Hyprland, so the lock
   cannot block it — this is deliberate.
3. **systemd:** `systemctl --user stop kidlock` (its `ExecStop=` unlocks).
4. **Compositor reset:** `hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'`
   returns to the normal submap even if the state file disagrees.
5. **Nuclear:** `hyprctl reload` + step 4 (reload re-registers binds from config
   but does not change the submap).

`kidlock doctor` diagnoses a broken install.

## Uninstall

```bash
./uninstall.sh
```

Unlocks first, stops/disables the service, removes widget, CLI, generated lua,
and the `require` line; reloads Hyprland. Your `kidlock.conf` is kept for review.
Manual restore if ever needed:
`hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'`.

## Security limitations (not a secure kiosk)

- **Privilege:** runs as the student user, so a knowledgeable user with a shell
  can run `kidlock unlock`. This stops *accidental* escapes, not a determined user.
- **VT switching** (`Ctrl+Alt+F1–F6`), **SysRq**, and the **power button** are
  kernel-level and cannot be blocked from Hyprland (VT-switch doubles as recovery).
- **Virtual keyboards bypass bind matching.** Verified live on Hyprland 0.56:
  keys injected via the virtual-keyboard protocol (`wtype`, and by extension
  on-screen keyboards using that protocol) do not trigger compositor binds —
  neither default binds (e.g. volume keys) nor kidlock swallows. A student able
  to run such a tool could send combos straight to the client app. Mitigation
  for stricter setups: don't install/provide virtual keyboards or shell access.
- **Other devices/sessions:** USB devices plugged in later, SSH sessions, a
  second concurrent login, or another window-manager session are unaffected.
- **Global shortcuts** (xdg GlobalShortcuts, IME hotkeys) and **touchpad
  gestures** live outside keybind submaps and may still fire.
- **Caps Lock / Num Lock** state and on-screen keyboards are untouched.
- For real kiosk enforcement you need OS-level lockdown (dedicated user, polkit,
  disabled VTs, fullscreen kiosk shell) — this plugin is one layer, not the wall.

## Validation status (read before classroom use)

- **Verified live:** submap enter/exit (`hyprctl submap`), 806 correctly
  registered swallow binds (keysyms + modmasks inspected), lock/unlock/toggle/
  status roundtrips, Waybar JSON both states, no-daemon recovery, session scope,
  reload semantics, install/uninstall, widget renders without QML errors.
  (`tests/smoke.sh`: 31/31 PASS.)
- **Requires a physical keyboard check:** pass-through of normal typing and
  swallowing of combos for *physical* (libinput) keys could not be exercised
  from the test session — no physical access, `/dev/uinput` is root-only, and
  `wtype` (virtual-keyboard protocol) provably bypasses bind matching here, so
  it is not a valid stand-in (see above). The binds it depends on are verified
  present and Hyprland consumes matched binds by default (`non_consuming=false`
  on all 806), but run `TESTING.md` items 1–14 on the real keyboard before
  relying on the lock.

## Known limitations

- Hyprland-Lua only; no X11/other compositors.
- `hyprctl reload` keeps the current submap (verified): reloading while locked
  keeps you locked (binds re-register). Reloading after a *broken* config edit
  can drop binds — `kidlock doctor` detects this.
- Non-US layouts: letters are matched by XKB keysym, which is layout-aware for
  the common cases; AltGr/ISO_Level3 typing is unaffected (AltGr ≠ Alt).
- The Quickshell widget polls every 1.5 s + watches the state file; state
  flips within ~a second of a toggle.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `kidlock lock` → "submap unknown" | `kidlock apply-config`, check `require("hypr.kidlock")` in bindings.lua, `hyprctl reload`, `kidlock doctor` |
| Click toggles but shortcuts still work | compositor didn't enter submap: `hyprctl submap` should print `kidlock`; run `kidlock doctor` |
| Typing broken while locked | a bare typing key got bound — `hyprctl -j binds` → look for your key in submap `kidlock`; report it |
| Widget shows stale state | it polls; wait 2 s. If stuck, the widget's Process can't find `kidlock` — check `~/.local/bin` on PATH |
| Bar missing after Omarchy update | reinstall widget: `./install.sh` (config + lua are kept/regenerated) |
| `hyprctl reload` errors | `hyprctl configerrors`; a `pcall` guards every generated bind, so kidlock.lua itself won't abort config load |

## Files

```
bin/kidlock                 CLI (lock/unlock/toggle/status/boot/apply-config/doctor)
lib/generate_lua.py         BLOCK_* config -> Hyprland submap binds (no deps)
config/kidlock.conf         admin config (installed to ~/.config/kidlock/)
quickshell/kidlock.keyboard-lock/   native Omarchy bar widget (centre)
waybar/                     Waybar custom-module snippet + CSS
systemd/kidlock.service     user unit: boot applies initial state, stop unlocks
tests/smoke.sh              automated checks   TESTING.md  manual checklist
LICENSE                     MIT   install.sh / uninstall.sh   .gitignore
```
