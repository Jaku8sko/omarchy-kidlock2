#!/usr/bin/env bash
# uninstall.sh -- remove kidlock and restore the session to normal.
# Order matters: unlock FIRST (while the submap still exists), then remove.
set -u

BIN_DIR="${HOME}/.local/bin"
HYPR_DIR="${HOME}/.config/hypr"
PLUGIN_DIR="${HOME}/.config/omarchy/plugins/kidlock.keyboard-lock"
UNIT_DIR="${HOME}/.config/systemd/user"

log() { printf 'uninstall: %s\n' "$*"; }

# 1. Unlock while we still can --------------------------------------------------
if [ -x "${BIN_DIR}/kidlock" ]; then
    "${BIN_DIR}/kidlock" unlock 2>/dev/null || "${BIN_DIR}/kidlock" status >/dev/null 2>&1 || true
    log "unlock attempted"
fi

# 2. Stop + disable the service ---------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now kidlock.service 2>/dev/null || true
    log "service disabled/stopped (if present)"
fi
rm -f "${UNIT_DIR}/kidlock.service"

# 3. Remove the bar widget ----------------------------------------------------------
if [ -d "${PLUGIN_DIR}" ]; then
    rm -rf "${PLUGIN_DIR}"
    log "removed Quickshell widget files"
    # omarchy-bar has no 'remove' verb; the layout entry for the missing
    # widget is ignored on next shell start. To clean it now, either:
    #   omarchy bar reset      # restore Omarchy default bar layout, or
    #   re-put your widgets manually (see README).
    log "note: remove the stale layout entry with 'omarchy bar reset' if the bar complains"
fi

# 4. Unhook + remove Hyprland integration ----------------------------------------------
if [ -f "${HYPR_DIR}/bindings.lua" ]; then
    # Delete only the line this installer added (idempotent, surgical).
    sed -i '/hypr\.kidlock/d' "${HYPR_DIR}/bindings.lua"
    log "removed require from bindings.lua"
fi
rm -f "${HYPR_DIR}/kidlock.lua"
log "removed generated kidlock.lua"

# 5. CLI + state ------------------------------------------------------------------------
rm -f "${BIN_DIR}/kidlock" "${BIN_DIR}/kidlock-generate-lua"
rm -rf "${XDG_RUNTIME_DIR:-${HOME}/.cache}/kidlock"
rm -rf "${HOME}/.cache/kidlock"
log "removed CLI and runtime state"

# 6. Reload compositor so the kidlock submap is fully gone -------------------------------
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
    sleep 1
    sub="$(hyprctl submap 2>/dev/null | head -n1)"
    log "current submap after reload: ${sub}"
fi

cat <<EOF

Uninstall complete. Kept on purpose (review, then delete by hand):
  * ~/.config/kidlock/kidlock.conf   (your admin config)
  * ~/.config/waybar/kidlock-*       (only if --with-waybar was used)
Normal keyboard behaviour is restored. If anything still feels wrong:
  hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'
EOF
