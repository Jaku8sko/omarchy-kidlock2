#!/usr/bin/env bash
# install.sh -- install the kidlock prototype into the current user session.
# No root required. Safe to re-run (idempotent).
#
# Usage:
#   ./install.sh                 # Quickshell bar (Omarchy 4 default)
#   ./install.sh --with-waybar   # also install the Waybar module files
#   ./install.sh --no-bar        # skip bar widget installation
#   ./install.sh --no-autostart  # skip enabling the systemd user unit
set -u

WITH_WAYBAR=0
WITH_BAR=1
WITH_AUTOSTART=1
for arg in "$@"; do
    case "${arg}" in
        --with-waybar) WITH_WAYBAR=1 ;;
        --no-bar) WITH_BAR=0 ;;
        --no-autostart) WITH_AUTOSTART=0 ;;
        *) echo "unknown flag: ${arg}" >&2; exit 2 ;;
    esac
done

SRC="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONF_DIR="${HOME}/.config/kidlock"
HYPR_DIR="${HOME}/.config/hypr"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/kidlock.keyboard-lock"
UNIT_DIR="${HOME}/.config/systemd/user"

log() { printf 'install: %s\n' "$*"; }
warn() { printf 'install: WARNING: %s\n' "$*" >&2; }
die() { printf 'install: ERROR: %s\n' "$*" >&2; exit 1; }

# 0. Preflight: fail fast with a clear message on a fresh machine -------------
command -v python3 >/dev/null 2>&1 || die "python3 not found (required by the lua generator)"
if command -v hyprctl >/dev/null 2>&1; then
    # Best effort: kidlock needs the Hyprland Lua API (define_submap/no_op),
    # present on Omarchy 4 / Hyprland 0.56+. Anything older is a hard stop.
    HYPR_VER="$(hyprctl version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    if [ -n "${HYPR_VER}" ]; then
        log "Hyprland ${HYPR_VER} detected"
        case "${HYPR_VER}" in
            0.5[6-9]*|0.[6-9]*|[1-9]*) ;;
            *) warn "Hyprland ${HYPR_VER} predates the Lua config API this plugin needs -- install will continue but 'kidlock doctor' will fail; Omarchy 4 / Hyprland 0.56+ required" ;;
        esac
    fi
else
    warn "hyprctl not found -- installing files only; run inside Hyprland and re-run './install.sh' to hook up binds + bar"
fi
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || warn "no Hyprland session detected (HYPRLAND_INSTANCE_SIGNATURE empty) -- installing anyway; run 'kidlock doctor' inside Hyprland later"

# 1. CLI ---------------------------------------------------------------------
mkdir -p "${BIN_DIR}"
cp "${SRC}/bin/kidlock" "${BIN_DIR}/kidlock"
chmod +x "${BIN_DIR}/kidlock"
cp "${SRC}/lib/generate_lua.py" "${BIN_DIR}/kidlock-generate-lua"
chmod +x "${BIN_DIR}/kidlock-generate-lua"
log "installed ${BIN_DIR}/kidlock + kidlock-generate-lua (ensure ~/.local/bin is on PATH)"

# 2. Config (never overwrite an existing admin config) ------------------------
mkdir -p "${CONF_DIR}"
if [ -f "${CONF_DIR}/kidlock.conf" ]; then
    log "kept existing ${CONF_DIR}/kidlock.conf"
else
    cp "${SRC}/config/kidlock.conf" "${CONF_DIR}/kidlock.conf"
    log "installed ${CONF_DIR}/kidlock.conf (edit owner/initial state here)"
fi

# 3. Hyprland submap binds ----------------------------------------------------
mkdir -p "${HYPR_DIR}"
python3 "${SRC}/lib/generate_lua.py" --config "${CONF_DIR}/kidlock.conf" --output "${HYPR_DIR}/kidlock.lua"
REQUIRE_LINE='require("hypr.kidlock")  -- kidlock keyboard-lock submap (managed by install.sh)'
if [ -f "${HYPR_DIR}/bindings.lua" ]; then
    if grep -q 'hypr\.kidlock' "${HYPR_DIR}/bindings.lua"; then
        log "bindings.lua already requires hypr.kidlock"
    else
        printf '\n%s\n' "${REQUIRE_LINE}" >> "${HYPR_DIR}/bindings.lua"
        log "appended require to ${HYPR_DIR}/bindings.lua"
    fi
else
    warn "no ${HYPR_DIR}/bindings.lua -- add '${REQUIRE_LINE}' to your Hyprland lua config manually"
fi

# 4. Bar widget ----------------------------------------------------------------
if [ "${WITH_BAR}" -eq 1 ]; then
    mkdir -p "${PLUGIN_DIR}"
    cp "${SRC}/quickshell/kidlock.keyboard-lock/manifest.json" "${PLUGIN_DIR}/manifest.json"
    cp "${SRC}/quickshell/kidlock.keyboard-lock/BarWidget.qml" "${PLUGIN_DIR}/BarWidget.qml"
    log "installed Quickshell widget -> ${PLUGIN_DIR}"
    if command -v omarchy >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        # Place it in the centre of the bar (best effort; layout may differ).
        if omarchy bar put kidlock.keyboard-lock --section center 2>/dev/null; then
            log "placed widget in bar centre"
        else
            warn "could not auto-place widget; run:  omarchy bar put kidlock.keyboard-lock --section center"
        fi
    else
        log "place the widget with:  omarchy bar put kidlock.keyboard-lock --section center"
    fi
fi

# 5. Waybar files (opt-in; Omarchy 4 uses Quickshell by default) ----------------
if [ "${WITH_WAYBAR}" -eq 1 ]; then
    mkdir -p "${HOME}/.config/waybar"
    cp "${SRC}/waybar/waybar-module.jsonc" "${HOME}/.config/waybar/kidlock-module.jsonc"
    cp "${SRC}/waybar/kidlock.css" "${HOME}/.config/waybar/kidlock.css"
    log "installed Waybar snippet + css to ~/.config/waybar (merge manually; see README)"
fi

# 6. systemd user unit ----------------------------------------------------------
mkdir -p "${UNIT_DIR}"
cp "${SRC}/systemd/kidlock.service" "${UNIT_DIR}/kidlock.service"
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
    if [ "${WITH_AUTOSTART}" -eq 1 ]; then
        systemctl --user enable kidlock.service 2>/dev/null \
            && log "enabled kidlock.service (applies initial state at login)" \
            || warn "could not enable kidlock.service (no user bus?); enable later: systemctl --user enable kidlock.service"
    fi
fi

# 7. Load the new binds + sanity check ------------------------------------------
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    if hyprctl reload >/dev/null 2>&1; then
        sleep 1
        log "reloaded Hyprland config"
    else
        warn "hyprctl reload failed; reload manually"
    fi
    export PATH="${BIN_DIR}:${PATH}"
    if kidlock doctor; then
        log "doctor: all checks pass"
    else
        warn "doctor reported problems (see above)"
    fi
fi

cat <<EOF

Done. Next steps:
  * Ensure ~/.local/bin is on PATH, then:   kidlock lock     (test the lock)
  * Click the lock icon in the bar centre to toggle (mouse).
  * Emergency unlock from any shell (SSH, VT, terminal):  kidlock unlock
  * Docs: README.md (usage, recovery, limitations), TESTING.md (checklist).
EOF
