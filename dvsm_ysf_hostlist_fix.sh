#!/bin/bash
###############################################################################
#
#  dvsm_ysf_hostlist_fix.sh
#
#  Fixes two long-standing bugs in the DVSwitch helper script (dvswitch.sh)
#  that affect the YSF room list used by the DVSwitch Mobile app:
#
#  1) ParseYSFile built each list entry with the reflector IP:port as the
#     dial value instead of the numeric reflector ID. YSF DG-ID only works
#     when a room is linked BY ID (linking by IP skips the connect/registration
#     procedure), so with IP:port entries the DG-ID never applies.
#         print(fields[3] + ":" + fields[4] + "|||" + fields[1])   # IP:port
#     becomes
#         print(fields[0] + "|||" + fields[1])                     # ID
#
#  2) "./dvswitch.sh update" failed for YSF with
#         Error, YSFHosts.txt file does not seem to be valid
#     because downloadAndValidate checks the freshly downloaded host file for
#     the literal string "dvswitch.org", which the current Pi-Star / DVRef
#     generated file no longer contains. The YSF validation token is changed
#     from "dvswitch.org" to "Pi-Star" (present in every Pi-Star host file),
#     so the update no longer aborts. Only the YSF line is touched.
#
#  Both changes are confined to the YSF path. DMR, NXDN, P25 and D-Star use
#  their own parse functions and validation lines and are left untouched.
#
#  After patching, any existing YSF_node_list.txt still holding IP:port
#  entries is regenerated from the local YSFHosts.txt so the fix takes effect
#  immediately (one-off catch-up; future regenerations are already correct).
#
#  Usage:   sudo ./dvsm_ysf_hostlist_fix.sh            patch (idempotent)
#           sudo ./dvsm_ysf_hostlist_fix.sh --rollback restore dvswitch.sh
#
#  IZ7EXI - 2026
#
###############################################################################

set -u

DVS_SH="${DVS_SH:-/opt/MMDVM_Bridge/dvswitch.sh}"
YSF_HOSTS="${YSF_HOSTS:-/var/lib/mmdvm/YSFHosts.txt}"
STAMP=$(date +%Y%m%d-%H%M%S)

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

[ "$(id -u)" -eq 0 ] || die "must be run as root (sudo)."

#--------------------------------------------------------------------------
# ROLLBACK
#--------------------------------------------------------------------------
if [ "${1:-}" = "--rollback" ]; then
        last=$(ls -1t "${DVS_SH}".*.bak 2>/dev/null | head -1)
        [ -n "${last}" ] || die "no backup of dvswitch.sh found."
        cp -a "${last}" "${DVS_SH}"
        echo "Restored ${DVS_SH} from $(basename "${last}")"
        echo "(regenerated node lists are left as they are)"
        exit 0
fi

[ -f "${DVS_SH}" ] || die "dvswitch.sh not found: ${DVS_SH} (set DVS_SH=... if elsewhere)"

#--------------------------------------------------------------------------
# 1. patch dvswitch.sh (both fixes, verified, idempotent)
#--------------------------------------------------------------------------
cp -a "${DVS_SH}" "${DVS_SH}.${STAMP}.bak"
info "backup: ${DVS_SH}.${STAMP}.bak"

DVS_SH="${DVS_SH}" python3 - << 'PY' || { echo "  restoring backup"; cp -a "${DVS_SH}.${STAMP}.bak" "${DVS_SH}"; exit 1; }
import os, sys
p = os.environ['DVS_SH']
s = open(p).read()
orig = s

# --- fix 1: list value = ID, not IP:port ---------------------------------
old1 = 'print(fields[3] + ":" + fields[4] + "|||" + fields[1])'
new1 = 'print(fields[0] + "|||" + fields[1])'
if new1 in s and old1 not in s:
    print("  fix 1 (ID list): already applied")
else:
    c = s.count(old1)
    if c != 1:
        print("  ERROR fix 1: expected 1 match, found %d. Nothing saved." % c)
        sys.exit(1)
    s = s.replace(old1, new1, 1)
    print("  fix 1 (ID list): applied")

# --- fix 2: YSF validation token ------------------------------------------
old2 = 'downloadAndValidate "YSFHosts.txt" "YSF_Hosts.txt" "dvswitch.org"'
new2 = 'downloadAndValidate "YSFHosts.txt" "YSF_Hosts.txt" "Pi-Star"'
if new2 in s and old2 not in s:
    print("  fix 2 (YSF validation token): already applied")
else:
    c = s.count(old2)
    if c != 1:
        print("  ERROR fix 2: expected 1 match, found %d. Nothing saved." % c)
        sys.exit(1)
    s = s.replace(old2, new2, 1)
    print("  fix 2 (YSF validation token): applied")

if s != orig:
    open(p, 'w').write(s)
PY

# syntax sanity check; restore on failure
bash -n "${DVS_SH}" || { cp -a "${DVS_SH}.${STAMP}.bak" "${DVS_SH}"; die "syntax check failed, backup restored."; }
info "dvswitch.sh patched and syntax OK"

#--------------------------------------------------------------------------
# 2. one-off catch-up: regenerate existing YSF_node_list.txt with IDs
#--------------------------------------------------------------------------
if [ -f "${YSF_HOSTS}" ]; then
        found=0
        while IFS= read -r f; do
                found=1
                ip=$(grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:' "$f" 2>/dev/null)
                [ "${ip}" -gt 0 ] 2>/dev/null || { info "already by ID: $f"; continue; }
                cp -a "$f" "$f.${STAMP}.bak"
                { echo "disconnect|||Unlink";
                  grep -vE '^#' "${YSF_HOSTS}" | awk -F';' 'NF>=2 && $1!="" {print $1"|||"$2}'; } > "$f"
                info "regenerated (ID): $f"
        done < <(find / -name "YSF_node_list.txt" 2>/dev/null | grep -v /proc)
        [ "${found}" -eq 1 ] || info "no YSF_node_list.txt found to regenerate (will be built by the app)"
else
        info "note: ${YSF_HOSTS} not found, skipped list regeneration (set YSF_HOSTS=...)"
fi

echo
echo "DONE."
echo " - dvswitch.sh patched (backup ${DVS_SH}.${STAMP}.bak)"
echo " - YSF room list now uses reflector IDs, so DG-ID works when linking a room"
echo " - './dvswitch.sh update' no longer fails YSF validation"
echo
echo "In the DVSwitch Mobile app force a reload of the room list (disconnect and"
echo "reconnect, or switch mode away and back to YSF): the phone caches the old list."
echo
echo "To undo:  $0 --rollback"
echo
echo "NOTE: NXDN and P25 use the same stale 'dvswitch.org' validation token and are"
echo "likely broken the same way; not touched here."
