# kidlock validation checklist (spec §16)

Automated: `./tests/smoke.sh` (covers binds, roundtrip, status JSON, typing
delivery when `wtype`+`foot` are available). Manual items below — record
PASS/FAIL + notes. Environment used for reference results: Omarchy 4.0.4,
Hyprland 0.56.2 (Lua API), Quickshell bar, `wtype` present, no Waybar installed.

## Typing (must keep working while LOCKED)

| # | Test | Result | Notes |
|---|---|---|---|
| 1 | Letters + numbers (`The quick 123`) | | |
| 2 | Space, Enter, Backspace, Delete | | |
| 3 | Uppercase via Shift (`ABC !@#`) | | bare Shift is never bound |
| 4 | Punctuation (`.,;/[]-='`) | | |

## Shortcuts (must be swallowed while LOCKED)

| # | Test | Result | Notes |
|---|---|---|---|
| 5 | `Ctrl+W` (close tab) | | |
| 6 | `Ctrl+Q` (quit app) | | |
| 7 | `Ctrl+T` (new tab) | | |
| 8 | `Ctrl+L` (focus URL bar) | | |
| 9 | `Ctrl+Alt+T` (terminal) | | |
| 10 | `Alt+F4` (close window) | | |
| 11 | `Alt+Tab` (switch window) | | |
| 12 | `Super+…` (launcher/workspaces) | | default binds inactive in submap |
| 13 | Hyprland workspace switching (`Super+1..0`) | | |
| 14 | Browser/app shortcuts generally | | |

## Interaction / lifecycle

| # | Test | Result | Notes |
|---|---|---|---|
| 15 | Mouse: click, scroll, select, bar control | | never bound/grabbed |
| 16 | Bar click locks | | |
| 17 | Bar click unlocks | | |
| 18 | Kill bar/widget/terminal → `kidlock unlock` from another shell recovers | | no daemon; compositor holds state |
| 19 | Logout/login → initial state applied | | via kidlock.service |
| 20 | Second user account unaffected | | per-session hyprctl socket |

## Reference results (2026-09-27, dev machine, single user)

- `tests/smoke.sh`: **31/31 PASS** (bind count/coverage 806, lock/unlock/
  toggle roundtrips, Waybar JSON both states, no-daemon unlock, typing-key
  non-binds, Shift non-bind).
- Quickshell widget: renders in bar centre without QML errors (screenshot +
  journal), `~/.local/bin` on the shell's PATH; click path = tested CLI.
- Waybar module: config reviewed, not live-tested (no Waybar on Omarchy 4;
  Quickshell widget is the live-tested path).
- Reload behaviour: `hyprctl reload` preserves submap, re-registers config
  binds, drops runtime-only binds — PASS (observed, documented as recovery note).
- Submap form: `define_submap("kidlock", "reset", fn)` auto-exits on the first
  unmatched key (observed); the 2-arg sticky form is used — PASS.
- Physical-keyboard matrix (items 1–14): **NOT YET RUN — REQUIRED before
  classroom use.** `wtype` cannot substitute: on this build virtual-keyboard
  input bypasses keybind matching entirely (volume binds and probe binds never
  fired), so only a real keyboard gives ground truth.
