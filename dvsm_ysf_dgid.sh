#!/bin/bash
###############################################################################
#
#  dvsm_ysf_dgid.sh  -  YSF DG-ID selection from the DVSwitch Mobile app menu
#
#  Adds a "YSF DG-ID" menu (decades 00-09 ... 90-99) to the DVSwitch Mobile
#  advanced menu. Selecting a value writes Options=nn in YSFGateway.ini,
#  restarts ysfgateway and automatically re-links the room you were on. The
#  callsign is left CLEAN (no -nn suffix): the DG-ID travels in the Options.
#
#  REQUIRES the patched YSFGateway (build_ysfgateway_options.sh): stock
#  YSFGateway only sends Options on a Startup= link, never on the remote
#  command that DVSwitch uses to link a room. Without the patch, Options
#  are written but never sent and the DG-ID has no effect.
#
#  Tested on: DVSwitch (Analog_Bridge + MMDVM_Bridge) with the patched
#             YSFGateway against a pYSFReflector3 multi-stream reflector.
#
#  Usage:   sudo ./dvsm_ysf_dgid.sh            install (idempotent)
#           sudo ./dvsm_ysf_dgid.sh --uninstall
#
#  IZ7EXI - 2026
#
###############################################################################

set -u

AB_DIR="${AB_DIR:-/opt/Analog_Bridge}"
SERVICE_YSF="${SERVICE_YSF:-ysfgateway}"
SERVICE_AB="${SERVICE_AB:-analog_bridge}"
MARK_BEGIN="# >>> YSF DGID BEGIN"
MARK_END="# <<< YSF DGID END"
STAMP=$(date +%Y%m%d-%H%M%S)

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

#--------------------------------------------------------------------------
# Pre-flight
#--------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must be run as root (sudo)."

[ -d "${AB_DIR}" ] || die "Analog_Bridge directory not found: ${AB_DIR}"
[ -f "${AB_DIR}/dvsm.sh" ] || die "${AB_DIR}/dvsm.sh not found: DVSwitch advanced menu is not installed."
[ -f "${AB_DIR}/dvsm.macro" ] || die "${AB_DIR}/dvsm.macro not found."
[ -f "${AB_DIR}/adv_main.txt" ] || die "${AB_DIR}/adv_main.txt not found."

# Real path of YSFGateway.ini: environment variable, then systemd unit,
# then standard path.
YSF_INI="${YSF_INI:-}"
if [ -z "${YSF_INI}" ] || [ ! -f "${YSF_INI}" ]; then
        YSF_INI=$(systemctl cat "${SERVICE_YSF}" 2>/dev/null \
                  | awk -F= '/^ExecStart=/{print $2}' | awk '{print $2}' | head -1)
fi
[ -n "${YSF_INI}" ] && [ -f "${YSF_INI}" ] || YSF_INI=/opt/YSFGateway/YSFGateway.ini
[ -f "${YSF_INI}" ] || die "YSFGateway.ini not found (looked for: ${YSF_INI})"

# Both services must exist, otherwise the restarts would fail silently
check_service() {
        systemctl list-unit-files 2>/dev/null | grep -q "^${1}\.service" \
                || systemctl status "${1}" >/dev/null 2>&1 \
                || die "service '${1}' not found. If it has another name on your system, run:
       ${2}=correct_name sudo -E $0"
}
check_service "${SERVICE_YSF}" SERVICE_YSF
check_service "${SERVICE_AB}"  SERVICE_AB

#--------------------------------------------------------------------------
# Removal of marked blocks (used by both install and uninstall)
#--------------------------------------------------------------------------
strip_block() {
        local f="$1"
        grep -q "${MARK_BEGIN}" "${f}" 2>/dev/null || return 0
        sed -i "\|${MARK_BEGIN}|,\|${MARK_END}|d" "${f}"
}

ensure_newline() { sed -i -e '$a\' "$1"; }

#--------------------------------------------------------------------------
# UNINSTALL
#--------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
        echo "Removing YSF DG-ID..."
        cp -a "${AB_DIR}/dvsm.sh"     "${AB_DIR}/dvsm.sh.${STAMP}.bak"
        cp -a "${AB_DIR}/dvsm.macro"  "${AB_DIR}/dvsm.macro.${STAMP}.bak"
        cp -a "${AB_DIR}/adv_main.txt" "${AB_DIR}/adv_main.txt.${STAMP}.bak"
        strip_block "${AB_DIR}/dvsm.sh"
        strip_block "${AB_DIR}/dvsm.macro"
        sed -i '/^\*ysfdgid,/d' "${AB_DIR}/adv_main.txt"
        rm -f "${AB_DIR}/adv_ysf_dgid.txt" "${AB_DIR}"/adv_dgid_[0-9].txt
        systemctl restart "${SERVICE_AB}"
        info "removed. Any leftover Options= line in ${YSF_INI} is left as is."
        exit 0
fi

#--------------------------------------------------------------------------
# INSTALL
#--------------------------------------------------------------------------
echo "Installing YSF DG-ID"
info "Analog_Bridge : ${AB_DIR}"
info "YSFGateway ini: ${YSF_INI}"

cp -a "${AB_DIR}/dvsm.sh"      "${AB_DIR}/dvsm.sh.${STAMP}.bak"
cp -a "${AB_DIR}/dvsm.macro"   "${AB_DIR}/dvsm.macro.${STAMP}.bak"
cp -a "${AB_DIR}/adv_main.txt" "${AB_DIR}/adv_main.txt.${STAMP}.bak"
cp -a "${YSF_INI}"             "${YSF_INI}.${STAMP}.bak"

# --- 1. menus: first level (tens) and second level (units) ----------------
{
        for d in 0 1 2 3 4 5 6 7 8 9; do
                printf '*dgidp#adv_dgid_%d.txt,.    DG-ID %d0-%d9\n' "$d" "$d" "$d"
        done
        echo '*mainmenu,---- MAIN MENU ----'
} > "${AB_DIR}/adv_ysf_dgid.txt"

for d in 0 1 2 3 4 5 6 7 8 9; do
        {
                for u in 0 1 2 3 4 5 6 7 8 9; do
                        printf '*dgid#%d%d,.    DG-ID %d%d\n' "$d" "$u" "$d" "$u"
                done
                echo '*ysfdgid,---- DG-ID MENU ----'
        } > "${AB_DIR}/adv_dgid_${d}.txt"
done
info "menus created (11 files, max 11 entries each)"

# --- 2. entry in the main menu --------------------------------------------
ensure_newline "${AB_DIR}/adv_main.txt"
grep -q '^\*ysfdgid,' "${AB_DIR}/adv_main.txt" \
        || echo '*ysfdgid,YSF DG-ID' >> "${AB_DIR}/adv_main.txt"

# --- 3. macros (only 3: well below the Analog_Bridge table limit) ---------
strip_block "${AB_DIR}/dvsm.macro"
ensure_newline "${AB_DIR}/dvsm.macro"
cat >> "${AB_DIR}/dvsm.macro" << EOF
${MARK_BEGIN}
ysfdgid = \${MACRO} adv_ysf_dgid.txt
dgidp   = \${MACRO}
dgid    = \${DVSM} dgid
${MARK_END}
EOF
info "macros added: ysfdgid, dgidp, dgid"

# --- 4. handler in dvsm.sh, inserted before exit 0 ------------------------
strip_block "${AB_DIR}/dvsm.sh"
sed -i '/^exit 0$/d' "${AB_DIR}/dvsm.sh"

cat >> "${AB_DIR}/dvsm.sh" << EOF
${MARK_BEGIN}
EOF

cat >> "${AB_DIR}/dvsm.sh" << 'EOF'
#################################################################
#  YSF DG-ID (multi-stream reflector: pYSFReflector3 / YCS)
#################################################################
if [ "$1" = "dgid" ]; then
        YSFGW=__YSF_INI__
        if [ ${mode_now} != "YSF" ]; then ${MESSAGE} " YSF  MODE  ONLY "; exit 0; fi
        case "$2" in ""|*[!0-9]*) ${MESSAGE} " INVALID  DG-ID "; exit 0;; esac
        dg=$((10#$2))
        if [ ${dg} -gt 99 ]; then ${MESSAGE} " DG-ID  OUT  OF  RANGE "; exit 0; fi
        dgp=$(printf "%02d" ${dg})
        ${MESSAGE} " WAIT   DG-ID ${dgp} "
        if [ ! -z "${TG}" ] && [ "${TG}" != "U" ] && [ "${TG}" != "disconnect" ]; then
                ${TUNE} disconnect
                sleep 2
        fi
        # The DG-ID travels in Options only; the callsign is never touched.
        if [ ${dg} -eq 0 ]; then
                sudo sed -i -e "/^Options=/d" ${YSFGW}
        elif [[ ! -z `grep "^Options=" ${YSFGW}` ]]; then
                sudo sed -i -e "/^Options=/ c Options=${dg};" ${YSFGW}
        else
                sudo sed -i -e "/^\[Network\]/a Options=${dg};" ${YSFGW}
        fi
        sudo systemctl restart __SERVICE_YSF__
        sleep 8
        if [ ! -z "${TG}" ] && [ "${TG}" != "U" ] && [ "${TG}" != "disconnect" ]; then
                ${TUNE} "${TG}"
                sleep 3
                if [ "$(${TUNE})" != "${TG}" ]; then ${TUNE} "${TG}"; sleep 2; fi
                ${MESSAGE} " OK   DG-ID ${dgp}   ${TG} "
        else
                ${MESSAGE} " OK   DG-ID ${dgp} "
        fi
fi
EOF

cat >> "${AB_DIR}/dvsm.sh" << EOF
${MARK_END}
exit 0
EOF

sed -i "s|__YSF_INI__|${YSF_INI}|; s|__SERVICE_YSF__|${SERVICE_YSF}|" "${AB_DIR}/dvsm.sh"
chmod 755 "${AB_DIR}/dvsm.sh"
bash -n "${AB_DIR}/dvsm.sh" || die "syntax error in dvsm.sh (restore ${AB_DIR}/dvsm.sh.${STAMP}.bak)"
info "handler installed in dvsm.sh"

# --- 5. restart Analog_Bridge to load the new macros ----------------------
systemctl restart "${SERVICE_AB}"

echo
echo "DONE. Reconnect the app: main menu -> YSF DG-ID -> tens -> value."
echo "Backups with timestamp ${STAMP} in ${AB_DIR} and next to the ini file."
echo
echo "Notes:"
echo " - requires the patched YSFGateway (build_ysfgateway_options.sh),"
echo "   otherwise the Options are written but never sent"
echo " - works in YSF mode only; the callsign stays clean (no suffix)"
echo " - DG-ID 00 removes Options: back to the reflector default stream"
echo " - the reflector must have that DG-ID active, otherwise you stay on default"
echo " - after the selection the gateway restarts and re-links by itself (~13 s)"
