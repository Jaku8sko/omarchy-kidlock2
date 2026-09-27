#!/usr/bin/env bash
# tests/smoke.sh -- automated checks for the kidlock prototype.
# Run inside a Hyprland session:  ./tests/smoke.sh
# Exits non-zero on failure. The interactive wtype test is best-effort
# (skipped cleanly when wtype/foot are unavailable or focus is uncertain).
set -u

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP: %s\n' "$*"; }

command -v kidlock >/dev/null 2>&1 || { echo "FAIL: kidlock not on PATH (run install.sh first)"; exit 1; }

# 1. doctor ---------------------------------------------------------------------
kidlock doctor >/tmp/kidlock-smoke-doctor.log 2>&1 && ok "doctor passes" || { fail "doctor fails"; cat /tmp/kidlock-smoke-doctor.log; }

# 2. kidlock submap registered with a sane number of swallow binds ---------------
# Helper: query kidlock-submap binds as "modmask:key" lines via python (the
# -j output is pretty-printed multi-line JSON, so line-grep cannot correlate
# fields within one bind object).
kid_binds() {
    hyprctl -j binds 2>/dev/null | python3 -c "
import json,sys
for b in json.load(sys.stdin):
    if b.get('submap') == 'kidlock':
        print('%s:%s' % (b.get('modmask'), b.get('key')))
"
}
KID_BINDS="$(kid_binds)"
COUNT="$(printf '%s\n' "${KID_BINDS}" | grep -c . || true)"
if [ "${COUNT}" -ge 300 ]; then ok "kidlock submap has ${COUNT} swallow binds (>=300)"; else fail "only ${COUNT} kidlock binds (expected >=300)"; fi
for probe in W Escape Tab Left F1 Print Home Prior Super_L Delete SPACE; do
    if printf '%s\n' "${KID_BINDS}" | grep -q ":${probe}$"; then
        ok "swallow bind present for key ${probe}"
    else
        fail "missing swallow bind for key ${probe}"
    fi
done
# Spot-check modifier combos via modmask (CTRL=4, ALT=8, SUPER=64).
for probe in "4:W" "4:T" "4:L" "8:F4" "8:Tab" "64:SPACE" "64:Super_L"; do
    if printf '%s\n' "${KID_BINDS}" | grep -q "^${probe}$"; then
        ok "swallow bind present for ${probe} (modmask:key)"
    else
        fail "missing swallow bind for ${probe} (modmask:key)"
    fi
done

# 3. Typing keys must NOT be swallowed (no bare-modmask binds on plain "A") ----
if printf '%s\n' "${KID_BINDS}" | grep -q "^0:A$"; then
    fail "bare A is bound in kidlock submap (typing would break!)"
else
    ok "bare A unbound (typing passes through)"
fi
# Bare Shift must never be swallowed either (uppercase/punctuation need it).
if printf '%s\n' "${KID_BINDS}" | grep -q "^0:Shift_L$\|^0:Shift_R$"; then
    fail "bare Shift is bound (Shift-typing would break!)"
else
    ok "bare Shift unbound (Shift-typing works)"
fi

# 4. lock/unlock roundtrip ---------------------------------------------------------
START_SUB="$(hyprctl submap 2>/dev/null | head -n1)"
kidlock lock >/dev/null 2>&1 && [ "$(hyprctl submap | head -n1)" = "kidlock" ] \
    && [ "$(kidlock status)" = "LOCKED" ] \
    && ok "lock -> submap=kidlock, status=LOCKED" \
    || fail "lock roundtrip"
kidlock unlock >/dev/null 2>&1 && [ "$(kidlock status)" = "UNLOCKED" ] \
    && ok "unlock -> status=UNLOCKED" \
    || fail "unlock roundtrip"
kidlock toggle >/dev/null 2>&1 && [ "$(kidlock status)" = "LOCKED" ] \
    && ok "toggle locks" || fail "toggle locks"
kidlock toggle >/dev/null 2>&1 && [ "$(kidlock status)" = "UNLOCKED" ] \
    && ok "toggle unlocks" || fail "toggle unlocks"
[ "$(hyprctl submap | head -n1)" = "${START_SUB}" ] && ok "submap restored to ${START_SUB}" || fail "submap not restored"

# 5. Waybar JSON ----------------------------------------------------------------------
if kidlock status --waybar | grep -q '"class":"unlocked"'; then ok "waybar JSON (unlocked)"; else fail "waybar JSON"; fi
kidlock lock >/dev/null 2>&1
if kidlock status --waybar | grep -q '"class":"locked"'; then ok "waybar JSON (locked)"; else fail "waybar JSON locked"; fi
kidlock unlock >/dev/null 2>&1

# 6. Live typing test (best-effort: needs wtype + foot + focus) ------------------------
if command -v wtype >/dev/null 2>&1 && command -v foot >/dev/null 2>&1; then
    rm -f /tmp/kidlock-typeproof
    # A foot window that records exactly what the compositor delivers.
    foot --title kidlock-typetest -e sh -c 'cat > /tmp/kidlock-typeproof' >/dev/null 2>&1 &
    FOOTPID=$!
    sleep 1.2
    # NOTE: assumes the new foot window takes focus (Hyprland default).
    wtype 'abc123' 2>/dev/null && sleep 0.5 && printf '\004' | true
    # Send Ctrl+D via wtype to EOF the cat, then compare.
    wtype -M ctrl -k d -m ctrl 2>/dev/null || true
    sleep 0.8
    kill "${FOOTPID}" 2>/dev/null || true
    if [ -f /tmp/kidlock-typeproof ] && grep -q 'abc123' /tmp/kidlock-typeproof; then
        ok "live typing 'abc123' delivered to client"
    else
        skip "typing delivery uncertain (focus may have been elsewhere)"
    fi
    rm -f /tmp/kidlock-typeproof
else
    skip "wtype/foot unavailable for live typing test"
fi

# 7. Failure drill: unlock path does not depend on the bar ------------------------------
pkill -f 'kidlock' >/dev/null 2>&1 || true   # there is no daemon; must be a no-op
kidlock lock >/dev/null 2>&1 && kidlock unlock >/dev/null 2>&1 \
    && ok "CLI unlock works with no daemon involved" \
    || fail "CLI unlock"

printf '\nRESULT: %d pass, %d fail, %d skip\n' "${PASS}" "${FAIL}" "${SKIP}"
[ "${FAIL}" -eq 0 ]
