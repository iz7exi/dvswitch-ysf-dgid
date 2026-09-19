# YSF DG-ID per DVSwitch Mobile

Aggiunge al menu avanzato dell'app **DVSwitch Mobile** una voce **YSF DG-ID** che permette di
selezionare il DG-ID (00-99) da usare su un reflector C4FM multiflusso, direttamente dal
telefono, senza toccare file di configurazione e senza accedere via SSH.

Selezionando un valore, lo script sul nodo imposta il suffisso `-nn` sul nominativo di
YSFGateway e la riga `Options=nn`, riavvia il gateway e **riaggancia da solo la room su cui
eri**. L'operazione richiede circa 13 secondi e non serve rifare il tune a mano.

## A cosa serve

I reflector C4FM multiflusso (pYSFReflector3, YCS) separano il traffico in più stream in base
al DG-ID. Un radio Yaesu lo imposta dalla manopola DG; un nodo DVSwitch, che genera il flusso
YSF partendo da audio analogico, non ha quella manopola e finisce sempre sullo stream di
default del reflector. Questo script fornisce l'equivalente della manopola, come voce di menu
nell'app.

## Prerequisiti

- DVSwitch con **Analog_Bridge** e **MMDVM_Bridge** installati
- menu avanzato DVSwitch (`dvsm.sh`, `dvsm.macro`, `adv_main.txt` in `/opt/Analog_Bridge/`)
- **YSFGateway** gestito da systemd
- nominativo base in `[General]` di `YSFGateway.ini` di **massimo 7 caratteri**
  (il campo YSF è di 10 e il suffisso `-nn` ne occupa 3)
- un reflector che gestisca i DG-ID (pYSFReflector3 o YCS)

## Installazione

```bash
wget https://raw.githubusercontent.com/iz7exi/dvswitch-ysf-dgid/main/dvsm_ysf_dgid.sh
chmod +x dvsm_ysf_dgid.sh
sudo ./dvsm_ysf_dgid.sh
```

Poi riconnetti l'app: **menu principale → YSF DG-ID → decina → valore**.

Lo script è idempotente: si può rilanciare senza duplicare nulla. Prima di ogni modifica
crea copie di backup con timestamp di `dvsm.sh`, `dvsm.macro`, `adv_main.txt` e
`YSFGateway.ini` nelle rispettive directory.

### Percorsi e nomi servizio diversi

Il percorso di `YSFGateway.ini` viene ricavato automaticamente dall'unit systemd. Se il tuo
sistema usa percorsi o nomi di servizio diversi:

```bash
AB_DIR=/opt/Analog_Bridge \
YSF_INI=/opt/YSFGateway/YSFGateway.ini \
SERVICE_YSF=ysfgateway \
SERVICE_AB=analog_bridge \
sudo -E ./dvsm_ysf_dgid.sh
```

## Disinstallazione

```bash
sudo ./dvsm_ysf_dgid.sh --uninstall
```

Rimuove menu, macro e handler. La riga `Suffix` in `YSFGateway.ini` resta commentata: se ti
serve, riattivala a mano.

## Note operative

- funziona **solo in modalità YSF**: in altri modi l'app risponde `Solo in modalita YSF`
- **DG-ID 00** rimuove suffisso e `Options`: si torna allo stream di default del reflector
- il DG-ID scelto deve essere **attivo sul reflector**, altrimenti si resta sul default
- lo script commenta `Suffix` in `YSFGateway.ini`: senza questa modifica il nominativo viene
  troncato a 10 caratteri (`IK0AAA-37-`) e il reflector non riconosce il DG-ID.
  Di conseguenza **il nodo si presenta come `CALL-nn` su tutte le reti YSF**, non solo sul
  reflector multiflusso
- su reflector che non gestiscono i DG-ID (YSFReflector classico, FCS) il menu funziona ma
  non produce alcun effetto

## Come funziona

| Componente | Ruolo |
|---|---|
| `adv_ysf_dgid.txt` | menu di primo livello, 10 fasce di decina |
| `adv_dgid_0..9.txt` | menu di secondo livello, 10 valori ciascuno |
| `dvsm.macro` | 3 macro: `ysfdgid`, `dgidp`, `dgid` |
| `dvsm.sh` | handler `dgid <nn>`: scrive la configurazione, riavvia il gateway, riaggancia la room |

Le voci di menu usano la sintassi con argomento della dial string (`*dgid#37`), quindi per
tutti i 100 valori servono solo 3 macro: le tabelle di Analog_Bridge restano ampiamente
sotto i limiti.

## Testato su

- DVSwitch su armbian (rk322x), YSFGateway-20200908
- reflector pYSFReflector3 con gestione DG-ID

## Licenza

MIT

## Autore

IZ7EXI — rete MP-BAT, Barletta
