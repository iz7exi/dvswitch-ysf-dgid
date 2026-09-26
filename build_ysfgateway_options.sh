#!/bin/bash
###############################################################################
#
#  build_ysfgateway_options.sh
#
#  Builds YSFGateway with a one-line fix so that the Options (DG-ID booking)
#  are also sent when the reflector is linked by REMOTE COMMAND, which is how
#  DVSwitch links rooms.
#
#  Upstream YSFGateway sets the options only in startupLinking() and
#  reconnectReflector(), i.e. only for the automatic "Startup=" connection.
#  A node that links on demand (DVSwitch, WiresX) never sends them, in any
#  version, current master included. This patch adds the missing call.
#
#  The build keeps the same source revision the DVSwitch package ships
#  (2020-09-08), so nothing else changes in behaviour.
#
#  Usage:  sudo ./build_ysfgateway_options.sh
#          sudo ./build_ysgateway_options.sh --rollback
#
#  IZ7EXI - 2026
#
###############################################################################

set -u

SRC_DIR="${SRC_DIR:-/usr/src/YSFClients}"
TARGET="${TARGET:-/opt/YSFGateway/YSFGateway}"
SERVICE="${SERVICE:-ysfgateway}"
# Commit e750390 "Fix networking issues" (04/11/2020): il primo che NON apre
# il socket verso i reflector all'avvio, quindi parte con l'ini stile DVSwitch.
# Il commit del 08/09/2020 apriva il socket subito e non parte (bug noto).
REV_PIN="${REV_PIN:-e750390}"
STAMP=$(date +%Y%m%d-%H%M%S)

die()  { echo "ERRORE: $*" >&2; exit 1; }
info() { echo "  $*"; }

[ "$(id -u)" -eq 0 ] || die "va eseguito come root (sudo)."

#--------------------------------------------------------------------------
# ROLLBACK
#--------------------------------------------------------------------------
if [ "${1:-}" = "--rollback" ]; then
        last=$(ls -1t "${TARGET}".*.bak 2>/dev/null | head -1)
        [ -n "${last}" ] || die "nessun backup del binario trovato."
        systemctl stop "${SERVICE}"
        cp -a "${last}" "${TARGET}"
        systemctl start "${SERVICE}"
        echo "Ripristinato ${TARGET} da $(basename "${last}")"
        exit 0
fi

#--------------------------------------------------------------------------
# 1. strumenti
#--------------------------------------------------------------------------
for c in git make g++; do
        command -v $c >/dev/null || { info "installo gli strumenti di compilazione"; \
                apt-get update -qq && apt-get install -y -qq git build-essential || die "installazione fallita"; break; }
done

#--------------------------------------------------------------------------
# 2. sorgenti
#--------------------------------------------------------------------------
if [ -d "${SRC_DIR}/.git" ]; then
        info "sorgenti gia' presenti in ${SRC_DIR}"
        cd "${SRC_DIR}" && git fetch -q --all
else
        info "scarico i sorgenti in ${SRC_DIR}"
        git clone -q https://github.com/g4klx/YSFClients.git "${SRC_DIR}" || die "clone fallito"
        cd "${SRC_DIR}"
fi

cd "${SRC_DIR}"
git checkout -q -- . 2>/dev/null
REV="${REV_PIN}"
git checkout -q "${REV}" || die "checkout fallito (revisione ${REV})"
info "revisione: ${REV} ($(git log -1 --format=%ad --date=short))"

#--------------------------------------------------------------------------
# 3. patch
#--------------------------------------------------------------------------
cd "${SRC_DIR}/YSFGateway"
if grep -q "m_ysfNetwork->setOptions(m_options);" YSFGateway.cpp && \
   [ "$(grep -c 'setOptions(m_options)' YSFGateway.cpp)" -ge 3 ]; then
        info "patch gia' applicata"
else
        python3 - << 'PY' || exit 1
p = 'YSFGateway.cpp'
s = open(p).read()
old = '''\t\t\t\tLogMessage("Connect by remote command to %5.5s - \\"%s\\"", reflector->m_id.c_str(), reflector->m_name.c_str());

\t\t\t\tm_ysfNetwork->setDestination(reflector->m_name, reflector->m_addr, reflector->m_addrLen);'''
new = '''\t\t\t\tLogMessage("Connect by remote command to %5.5s - \\"%s\\"", reflector->m_id.c_str(), reflector->m_name.c_str());

\t\t\t\tm_ysfNetwork->setOptions(m_options);

\t\t\t\tm_ysfNetwork->setDestination(reflector->m_name, reflector->m_addr, reflector->m_addrLen);'''
if old not in s:
    raise SystemExit("ERRORE: il punto da modificare non e' stato trovato nel sorgente")
open(p, 'w').write(s.replace(old, new, 1))
print("  patch applicata")
PY
fi

#--------------------------------------------------------------------------
# 4. compila
#--------------------------------------------------------------------------
info "compilo"
make -s clean >/dev/null 2>&1
make -j"$(nproc)" >/tmp/ysfgw_build.log 2>&1 || { tail -20 /tmp/ysfgw_build.log; die "compilazione fallita (log completo: /tmp/ysfgw_build.log)"; }
[ -x ./YSFGateway ] || die "binario non prodotto"
info "compilato: $(./YSFGateway --version 2>&1 | head -1)"

#--------------------------------------------------------------------------
# 5. verifica che sia la versione attesa
#--------------------------------------------------------------------------
grep -aq "FileRoot" ./YSFGateway || die "il binario non ha il logging su file: revisione sbagliata"
grep -aq "YSFO"     ./YSFGateway || die "il binario non contiene il pacchetto options"
info "verifiche superate"

#--------------------------------------------------------------------------
# 6. installa con backup
#--------------------------------------------------------------------------
systemctl stop "${SERVICE}"
cp -a "${TARGET}" "${TARGET}.${STAMP}.bak"
cp -a ./YSFGateway "${TARGET}"
systemctl start "${SERVICE}"
sleep 5
systemctl is-active --quiet "${SERVICE}" || { info "il servizio non riparte, ripristino"; \
        cp -a "${TARGET}.${STAMP}.bak" "${TARGET}"; systemctl start "${SERVICE}"; \
        die "avvio fallito, binario originale ripristinato"; }

echo
echo "FATTO. Binario precedente salvato in ${TARGET}.${STAMP}.bak"
echo "Per tornare indietro:  $0 --rollback"
echo
echo "Ora le Options vengono inviate anche agganciando la room da DVSwitch."
echo "Verifica: metti Options=nn in [Network], aggancia la room per ID e"
echo "controlla sul dashboard del reflector di essere sul DG-ID nn con il"
echo "nominativo pulito, senza suffisso."
