# YSF DG-ID for DVSwitch Mobile

Adds a **YSF DG-ID** entry to the DVSwitch Mobile advanced menu, letting you pick the DG-ID
(00-99) to use on a multi-stream C4FM reflector straight from your phone — no configuration
files to edit, no SSH session needed.

When you select a value, the script on the node sets the `-nn` suffix on the YSFGateway
callsign and the `Options=nn` line, restarts the gateway and **re-links the room you were on
by itself**. It takes about 13 seconds; you do not have to re-tune manually.

## Why

Multi-stream C4FM reflectors (pYSFReflector3, YCS) split traffic into several streams based
on the DG-ID. A Yaesu radio sets it from the DG knob; a DVSwitch node, which builds the YSF
stream from analog audio, has no such knob and always ends up on the reflector's default
stream. This script provides the equivalent of that knob as a menu entry in the app.

## Requirements

- DVSwitch with **Analog_Bridge** and **MMDVM_Bridge**
- DVSwitch advanced menu (`dvsm.sh`, `dvsm.macro`, `adv_main.txt` in `/opt/Analog_Bridge/`)
- **YSFGateway** managed by systemd
- base callsign in `[General]` of `YSFGateway.ini` no longer than **7 characters**
  (the YSF field is 10 and the `-nn` suffix takes 3)
- a reflector with DG-ID management (pYSFReflector3 or YCS)

## Installation

```bash
wget https://raw.githubusercontent.com/iz7exi/dvswitch-ysf-dgid/main/dvsm_ysf_dgid.sh
chmod +x dvsm_ysf_dgid.sh
sudo ./dvsm_ysf_dgid.sh
```

Then reconnect the app: **main menu → YSF DG-ID → tens → value**.

The script is idempotent: running it again does not duplicate anything. Before any change it
creates timestamped backups of `dvsm.sh`, `dvsm.macro`, `adv_main.txt` and `YSFGateway.ini`
in their own directories.

### Different paths or service names

The path of `YSFGateway.ini` is derived automatically from the systemd unit. If your system
uses different paths or service names:

```bash
AB_DIR=/opt/Analog_Bridge \
YSF_INI=/opt/YSFGateway/YSFGateway.ini \
SERVICE_YSF=ysfgateway \
SERVICE_AB=analog_bridge \
sudo -E ./dvsm_ysf_dgid.sh
```

## Uninstall

```bash
sudo ./dvsm_ysf_dgid.sh --uninstall
```

Removes menus, macros and handler. The `Suffix` line in `YSFGateway.ini` is left commented
out: re-enable it by hand if you need it.

## Operating notes

- works in **YSF mode only**: in other modes the app replies `YSF MODE ONLY`
- **DG-ID 00** removes the suffix and `Options`: back to the reflector's default stream
- the DG-ID you pick must be **active on the reflector**, otherwise you stay on the default
  and it looks like nothing happened
- the script comments out `Suffix` in `YSFGateway.ini`: without that the callsign is
  truncated to 10 characters (`IK0AAA-37-`) and the reflector does not recognise the DG-ID.
  As a consequence **the node appears as `CALL-nn` on every YSF network**, not only on the
  multi-stream one
- on reflectors without DG-ID management (plain YSFReflector, FCS) the menu works but has no
  effect
- the setting is persistent: it survives a reboot. The room link does not, and has to be
  re-established

## How it works

| Component | Role |
|---|---|
| `adv_ysf_dgid.txt` | first-level menu, 10 bands of ten |
| `adv_dgid_0..9.txt` | second-level menus, 10 values each |
| `dvsm.macro` | 3 macros: `ysfdgid`, `dgidp`, `dgid` |
| `dvsm.sh` | handler `dgid <nn>`: writes the configuration, restarts the gateway, re-links the room |

Menu entries use the dial-string argument syntax (`*dgid#37`), so all 100 values need only 3
macros and the Analog_Bridge tables stay well below their limits.

## Tested on

- DVSwitch on armbian (rk322x) and Debian, YSFGateway-20200908
- pYSFReflector3 with DG-ID management

## License

MIT

## Author

**IZ7EXI** — MP-BAT network, Barletta, Italy
