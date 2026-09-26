# YSF DG-ID for DVSwitch Mobile

Adds a **YSF DG-ID** entry to the DVSwitch Mobile advanced menu, letting you pick the DG-ID
(00-99) to use on a multi-stream C4FM reflector straight from your phone — no configuration
files to edit, no SSH session needed.

Selecting a value writes `Options=nn` in `YSFGateway.ini`, restarts the gateway and re-links
the room you were on. The **callsign stays clean** — the DG-ID travels in the `Options`, not
in a `-nn` suffix, so your node identifies itself normally on every network.

## Two components

This repo has two parts, installed in order:

1. **`build_ysfgateway_options.sh`** — a patched YSFGateway. Stock YSFGateway only sends the
   `Options` on a `Startup=` link, never on the remote command that DVSwitch uses to link a
   room from the app. The patch adds the missing call so the DG-ID is actually sent. Without
   it, `Options` are written to the ini but never reach the reflector.
2. **`dvsm_ysf_dgid.sh`** — the menu itself: adds *YSF DG-ID* to the app, and on selection
   writes `Options=nn` and restarts the gateway.

## Why the patch is needed

YSFGateway sets the options only in `startupLinking()` (the automatic `Startup=` connection).
The remote-command path — the one DVSwitch triggers when you pick a room — does
`setDestination()` + `writePoll()` but **never** `setOptions()`, in every version including
current master. The patch is a single added line:

```cpp
LogMessage("Connect by remote command to ...");
+
+ m_ysfNetwork->setOptions(m_options);
+
  m_ysfNetwork->setDestination(...);
```

The build script pins commit `e750390` (the first that starts cleanly with the DVSwitch-style
ini) and applies this patch.

## Dependencies

The build script compiles YSFGateway on the node, so it needs **git, make and g++**. It tries
to install them automatically. On current systems that just works; on **end-of-life releases
(e.g. Debian Buster)** `apt` can no longer reach its archives and the auto-install fails — in
that case install them by hand first:

```bash
# normal systems
sudo apt-get install -y git make g++

# EOL release (Buster): archives need the valid-until check disabled
sudo apt-get -o Acquire::Check-Valid-Until=false update
sudo apt-get install -y --allow-unauthenticated git make g++
```

The menu script (`dvsm_ysf_dgid.sh`) needs nothing extra — only DVSwitch already installed.

## Installation

```bash
# 1. patched YSFGateway (compiles on the node, keeps the old binary, auto-rollback)
sudo ./build_ysfgateway_options.sh

# 2. the menu
sudo ./dvsm_ysf_dgid.sh
```

Then reconnect the app: **main menu → YSF DG-ID → tens → value**.

Both scripts are idempotent and make timestamped backups before any change.
`build_ysfgateway_options.sh --rollback` restores the previous binary;
`dvsm_ysf_dgid.sh --uninstall` removes the menu.

### Different paths or service names

```bash
AB_DIR=/opt/Analog_Bridge YSF_INI=/opt/YSFGateway/YSFGateway.ini \
SERVICE_YSF=ysfgateway SERVICE_AB=analog_bridge sudo -E ./dvsm_ysf_dgid.sh
```

## Link the room by ID, not by IP

The DG-ID only works on a room linked **by numeric ID** from `YSFHosts.txt`, not by raw
`IP:port`. Linking by ID runs the connect procedure that registers the node and carries the
options; linking by address just sets a destination and the reflector never learns the DG-ID.

```
22273|||C4FM_BAT                 <- works
82.85.236.36:42000|||C4FM_BAT    <- DG-ID has no effect
```

Find the ID with the reflector address: `grep -n "<address>" /var/lib/mmdvm/YSFHosts.txt`.

## Operating notes

- works in **YSF mode only**
- the callsign is never modified — the DG-ID is carried by `Options`
- **DG-ID 00** removes `Options`: back to the reflector's default stream
- the DG-ID must be **active on the reflector**, otherwise you stay on the default
- after the selection the gateway restarts and re-links the room by itself (~13 s)
- the setting survives a reboot; the room link does not

## Known limitation: YCS servers

On **YCS** reflectors this gives you connection, DG-ID registration and RX, but **not** TX on
a chosen DG-ID. YCS routes the *voice* by the DG-ID inside each frame's FICH, and MMDVM_Bridge
(DVSwitch) always transmits with FICH DG-ID 0 and offers no way to change it — a Yaesu radio
or an app like Z3DMR set the FICH, DVSwitch does not. On **pYSFReflector3**, which routes by
the registered node, the DG-ID works fully in TX and RX.

## How it works

| Component | Role |
|---|---|
| `adv_ysf_dgid.txt` | first-level menu, 10 bands of ten |
| `adv_dgid_0..9.txt` | second-level menus, 10 values each |
| `dvsm.macro` | 3 macros: `ysfdgid`, `dgidp`, `dgid` |
| `dvsm.sh` | handler `dgid <nn>`: writes `Options=nn`, restarts the gateway, re-links the room |

Menu entries use the dial-string argument syntax (`*dgid#37`), so all 100 values need only 3
macros.

## Tested on

- DVSwitch (Analog_Bridge + MMDVM_Bridge) on armbian (rk322x), patched YSFGateway
- pYSFReflector3 with DG-ID management

## License

MIT

## Author

**IZ7EXI** — MP-BAT network, Barletta, Italy
