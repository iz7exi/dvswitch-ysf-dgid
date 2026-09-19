#!/bin/bash
###############################################################################
#
#  dvsm_ysf_dgid.sh  -  YSF DG-ID selection from the DVSwitch Mobile app menu
#
#  Adds a "YSF DG-ID" menu (decades 00-09 ... 90-99) to the DVSwitch Mobile
#  advanced menu. Selecting a value sets the YSFGateway callsign suffix -nn
#  and Options=nn, restarts ysfgateway and automatically re-links the room
#  you were on.
#
#  Tested on: DVSwitch (Analog_Bridge + MMDVM_Bridge) with YSFGateway-20200908
#             against a pYSFReflector3 multi-stream reflector.
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

die() { echo "ERRORE: $*" >&2; exit 1; }
info() { echo "  $*"; }

#--------------------------------------------------------------------------
# Pre-flight
#--------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "va eseguito come root (sudo)."

[ -d "${AB_DIR}" ] || die "directory Analog_Bridge non trovata: ${AB_DIR}"
[ -f "${AB_DIR}/dvsm.sh" ] || die "${AB_DIR}/dvsm.sh non trovato: menu avanzato DVSwitch non installato."
[ -f "${AB_DIR}/dvsm.macro" ] || die "${AB_DIR}/dvsm.macro non trovato."
[ -f "${AB_DIR}/adv_main.txt" ] || die "${AB_DIR}/adv_main.txt non trovato."

# Percorso reale dell'ini di YSFGateway: variabile d'ambiente, poi unit systemd,
# poi percorso standard.
YSF_INI="${YSF_INI:-}"
if [ -z "${YSF_INI}" ] || [ ! -f "${YSF_INI}" ]; then
        YSF_INI=$(systemctl cat "${SERVICE_YSF}" 2>/dev/null \
                  | awk -F= '/^ExecStart=/{print $2}' | awk '{print $2}' | head -1)
fi
[ -n "${YSF_INI}" ] && [ -f "${YSF_INI}" ] || YSF_INI=/opt/YSFGateway/YSFGateway.ini
[ -f "${YSF_INI}" ] || die "YSFGateway.ini non trovato (cercato: ${YSF_INI})"

# I due servizi devono esistere, altrimenti i restart fallirebbero in silenzio
check_service() {
        systemctl list-unit-files 2>/dev/null | grep -q "^${1}\.service" \
                || systemctl status "${1}" >/dev/null 2>&1 \
                || die "servizio '${1}' non trovato. Se sul tuo sistema ha un altro nome, rilancia con:
       ${2}=nome_corretto sudo -E $0"
}
check_service "${SERVICE_YSF}" SERVICE_YSF
check_service "${SERVICE_AB}"  SERVICE_AB

#--------------------------------------------------------------------------
# Il campo nominativo YSF e' di 10 caratteri e il DG-ID viene aggiunto come
# "-nn" (3 caratteri): il Callsign base non puo' superare i 7 caratteri,
# altrimenti il nome arriva troncato al reflector e il DG-ID non viene
# riconosciuto. Verifica fatta PRIMA di toccare qualsiasi file.
#--------------------------------------------------------------------------
check_callsign() {
        local cs
        cs=$(sed -n '/^\[General\]/,/^\[Info\]/p' "${YSF_INI}" \
             | awk -F= '/^Callsign=/{print $2}' | head -1 | tr -d ' \r')
        cs="${cs%%-*}"
        [ -n "${cs}" ] || die "Callsign non trovato in [General] di ${YSF_INI}"
        if [ ${#cs} -gt 7 ]; then
                echo "ERRORE: Callsign base '${cs}' e' di ${#cs} caratteri." >&2
                echo "        Il campo YSF e' di 10 e il suffisso -nn ne usa 3:" >&2
                echo "        il massimo consentito e' 7 caratteri." >&2
                echo "        Accorcia Callsign in ${YSF_INI} e rilancia." >&2
                exit 1
        fi
        info "Callsign base : ${cs} (${#cs} caratteri, ok)"
}

#--------------------------------------------------------------------------
# Rimozione blocchi marcati (usata sia da install che da uninstall)
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
        echo "Rimozione YSF DG-ID..."
        cp -a "${AB_DIR}/dvsm.sh"     "${AB_DIR}/dvsm.sh.${STAMP}.bak"
        cp -a "${AB_DIR}/dvsm.macro"  "${AB_DIR}/dvsm.macro.${STAMP}.bak"
        cp -a "${AB_DIR}/adv_main.txt" "${AB_DIR}/adv_main.txt.${STAMP}.bak"
        strip_block "${AB_DIR}/dvsm.sh"
        strip_block "${AB_DIR}/dvsm.macro"
        sed -i '/^\*ysfdgid,/d' "${AB_DIR}/adv_main.txt"
        rm -f "${AB_DIR}/adv_ysf_dgid.txt" "${AB_DIR}"/adv_dgid_[0-9].txt
        systemctl restart "${SERVICE_AB}"
        info "rimosso. Il Suffix in ${YSF_INI} resta come lo trovi ora."
        exit 0
fi

#--------------------------------------------------------------------------
# INSTALL
#--------------------------------------------------------------------------
echo "Installazione YSF DG-ID"
info "Analog_Bridge : ${AB_DIR}"
info "YSFGateway ini: ${YSF_INI}"
check_callsign

cp -a "${AB_DIR}/dvsm.sh"      "${AB_DIR}/dvsm.sh.${STAMP}.bak"
cp -a "${AB_DIR}/dvsm.macro"   "${AB_DIR}/dvsm.macro.${STAMP}.bak"
cp -a "${AB_DIR}/adv_main.txt" "${AB_DIR}/adv_main.txt.${STAMP}.bak"
cp -a "${YSF_INI}"             "${YSF_INI}.${STAMP}.bak"

# --- 1. menu: primo livello (decine) e secondo livello (unita') ------------
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
info "menu creati (11 file, max 11 voci ciascuno)"

# --- 2. voce nel menu principale ------------------------------------------
ensure_newline "${AB_DIR}/adv_main.txt"
grep -q '^\*ysfdgid,' "${AB_DIR}/adv_main.txt" \
        || echo '*ysfdgid,YSF DG-ID' >> "${AB_DIR}/adv_main.txt"

# --- 3. macro (solo 3: sotto il limite della tabella di Analog_Bridge) -----
strip_block "${AB_DIR}/dvsm.macro"
ensure_newline "${AB_DIR}/dvsm.macro"
cat >> "${AB_DIR}/dvsm.macro" << EOF
${MARK_BEGIN}
ysfdgid = \${MACRO} adv_ysf_dgid.txt
dgidp   = \${MACRO}
dgid    = \${DVSM} dgid
${MARK_END}
EOF
info "macro aggiunte: ysfdgid, dgidp, dgid"

# --- 4. handler in dvsm.sh, inserito prima di exit 0 ----------------------
strip_block "${AB_DIR}/dvsm.sh"
sed -i '/^exit 0$/d' "${AB_DIR}/dvsm.sh"

cat >> "${AB_DIR}/dvsm.sh" << EOF
${MARK_BEGIN}
EOF

cat >> "${AB_DIR}/dvsm.sh" << 'EOF'
#################################################################
#  YSF DG-ID (reflector multiflusso: pYSFReflector3 / YCS)
#################################################################
if [ "$1" = "dgid" ]; then
        YSFGW=__YSF_INI__
        if [ ${mode_now} != "YSF" ]; then ${MESSAGE} " Solo in modalita YSF "; exit 0; fi
        case "$2" in ""|*[!0-9]*) ${MESSAGE} " DG-ID non valido "; exit 0;; esac
        dg=$((10#$2))
        if [ ${dg} -gt 99 ]; then ${MESSAGE} " DG-ID fuori range "; exit 0; fi
        dgp=$(printf "%02d" ${dg})
        base=$(grep "^Callsign=" ${YSFGW} | cut -d= -f2 | cut -d- -f1 | tr -d ' \r')
        [ -z "${base}" ] && base=${call_sign}
        if [ ${#base} -gt 7 ]; then ${MESSAGE} " CALL ${base} TROPPO LUNGO "; exit 0; fi
        ${MESSAGE} " WAIT   DG-ID ${dgp} "
        if [ ! -z "${TG}" ] && [ "${TG}" != "U" ] && [ "${TG}" != "disconnect" ]; then
                ${TUNE} disconnect
                sleep 2
        fi
        if [ ${dg} -eq 0 ]; then
                sudo sed -i -e "/^Callsign=/ c Callsign=${base}" ${YSFGW}
                sudo sed -i -e "/^Options=/d" ${YSFGW}
        else
                sudo sed -i -e "/^Callsign=/ c Callsign=${base}-${dgp}" ${YSFGW}
                if [[ ! -z `grep "^Options=" ${YSFGW}` ]]; then
                        sudo sed -i -e "/^Options=/ c Options=${dg};" ${YSFGW}
                else
                        sudo sed -i -e "/^\[Network\]/a Options=${dg};" ${YSFGW}
                fi
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
bash -n "${AB_DIR}/dvsm.sh" || die "errore di sintassi in dvsm.sh (ripristina ${AB_DIR}/dvsm.sh.${STAMP}.bak)"
info "handler installato in dvsm.sh"

# --- 5. Suffix: deve essere assente, altrimenti il nominativo viene troncato
if sed -n '/^\[General\]/,/^\[Info\]/p' "${YSF_INI}" | grep -q '^Suffix=..*'; then
        sed -i '/^\[General\]/,/^\[Info\]/ s/^Suffix=/# Suffix=/' "${YSF_INI}"
        info "Suffix commentato in ${YSF_INI} (obbligatorio: il campo nominativo e' di 10 caratteri)"
        systemctl restart "${SERVICE_YSF}"
fi

# --- 6. riavvio Analog_Bridge per caricare le nuove macro -----------------
systemctl restart "${SERVICE_AB}"

echo
echo "FATTO. Riconnetti l'app: menu principale -> YSF DG-ID -> decina -> valore."
echo "Backup con timestamp ${STAMP} nella directory ${AB_DIR} e accanto all'ini."
echo
echo "Note:"
echo " - funziona solo in modalita YSF"
echo " - DG-ID 00 rimuove suffisso e Options: torna allo stream di default"
echo " - il reflector deve avere quel DG-ID attivo, altrimenti resti sul default"
echo " - dopo la selezione il gateway si riavvia e si riaggancia da solo (~13 s)"
