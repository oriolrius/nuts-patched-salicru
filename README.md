# nuts-patched-salicru

Network UPS Tools (NUT) in a Docker image, built from source with a small patch
to the **Phoenixtec/Liebert HID** subdriver so that **Salicru SLC TWIN PRO2**
UPSes (USB `06da:ffff`, "PPC HID UPS") also report **real power, apparent power
and nominal real power** — values the hardware measures but stock NUT does not map.

Image: `ghcr.io/oriolrius/nuts-patched-salicru` (built & published by GitHub Actions).

## Why

These Salicru units enumerate as Phoenixtec `06da:ffff` and are handled by NUT's
`liebert-hid` subdriver. The stock **0.41** subdriver (NUT ≥ 2.8.5) already maps
input/output voltage, frequency and transfer thresholds. What it still omits are
the power readings, even though the device exposes them:

| NUT variable | HID path | added by |
|---|---|---|
| `ups.realpower` | `UPS.PowerConverter.Output.ActivePower` | **this patch** |
| `ups.power` | `UPS.PowerConverter.Output.ApparentPower` | **this patch** |
| `ups.realpower.nominal` | `UPS.Flow.[4].ConfigActivePower` | **this patch** |
| `input.voltage` | `UPS.PowerConverter.Input.[1].Voltage` | stock 0.41 |
| `input.frequency` | `UPS.PowerConverter.Input.[1].Frequency` | stock 0.41 |
| `output.voltage` / `output.frequency` | `UPS.PowerConverter.Output.*` | stock 0.41 |

> Note: many QNAP/Synology NAS boxes ship an **older** NUT whose subdriver is
> version **0.3**, which maps neither voltages nor power — which is why those
> appliances only show battery/load/status. This image fixes both.

The change: [`patches/0001-liebert-hid-salicru-power.patch`](patches/0001-liebert-hid-salicru-power.patch)
(full patched file vendored at `patches/liebert-hid.c`), against NUT **v2.8.5**.

## Run

```bash
docker run -d --name nut-salicru --restart unless-stopped \
  --privileged -v /dev/bus/usb:/dev/bus/usb \
  -p 3493:3493 \
  -e UPS_NAME=salicru -e VENDORID=06da -e PRODUCTID=ffff \
  ghcr.io/oriolrius/nuts-patched-salicru:latest

docker exec nut-salicru upsc salicru@127.0.0.1
```

Or `docker compose up -d` with the bundled `docker-compose.yml`.

### Environment

| Var | Default | Meaning |
|---|---|---|
| `UPS_NAME` | `ups` | NUT device name (`upsc <name>@host`) |
| `UPS_DESC` | `Salicru SLC TWIN PRO2` | description |
| `VENDORID` / `PRODUCTID` | `06da` / `ffff` | USB match |
| `LISTEN_ADDR` / `LISTEN_PORT` | `0.0.0.0` / `3493` | upsd bind |
| `POLLINTERVAL` | `2` | driver poll seconds |
| `ADMIN_USER` / `ADMIN_PASSWORD` | _(unset)_ | optional account for SET / battery test / beeper |

Reads (`upsc`) need no auth; only SET/instant-commands require the admin account.

## Deploy on nas1 (QNAP) — production cutover

The UPS USB can be owned by only one process. To run this container as the NUT
master **without losing the NAS's auto-shutdown**, put QTS into network-client mode:

1. **Stop QTS's native driver** so the container can claim the USB
   (Control Panel → External Device → UPS → switch from "UPS server" to
   **"Network UPS slave/client"**; or stop `usbhid-ups`/`upsd` on the host).
2. `docker compose up -d` this stack (it binds `:3493`).
3. Point QTS UPS **client** at the container's upsd IP (the NAS's own LAN IP / the
   published port). QTS now receives shutdown signals from the patched NUT.
4. Point **PeaNUT** (`ups.joor.net`) at the new upsd and confirm the extra
   variables appear.

See the in-repo `docker-compose.yml` for the exact service definition.

## Build locally

```bash
docker build -t nut-salicru:dev .
```

Pin a different NUT release with `--build-arg NUT_VERSION=2.8.5`.

## License

GPL-2.0-or-later (NUT is GPL-2.0+; this packaging and patch inherit it).
