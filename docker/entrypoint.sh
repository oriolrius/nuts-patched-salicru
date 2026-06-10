#!/bin/sh
# Generate NUT config from environment, start the USB HID driver, then run
# upsd in the foreground. Designed to run as a NUT *server* (master) that
# other hosts (e.g. a QNAP in network-client mode, or PeaNUT) connect to.
set -eu

UPS_NAME="${UPS_NAME:-ups}"
UPS_DESC="${UPS_DESC:-Salicru SLC TWIN PRO2}"
UPS_DRIVER="${UPS_DRIVER:-usbhid-ups}"
VENDORID="${VENDORID:-06da}"
PRODUCTID="${PRODUCTID:-ffff}"
POLLINTERVAL="${POLLINTERVAL:-2}"
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-3493}"
# Optional admin account for SET/instant-commands (battery test, beeper).
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

mkdir -p /etc/nut /var/run/nut
chmod 0770 /var/run/nut || true

cat > /etc/nut/ups.conf <<EOF
maxretry = 3
pollinterval = ${POLLINTERVAL}

[${UPS_NAME}]
    driver = ${UPS_DRIVER}
    port = auto
    vendorid = ${VENDORID}
    productid = ${PRODUCTID}
    desc = "${UPS_DESC}"
EOF

cat > /etc/nut/upsd.conf <<EOF
LISTEN ${LISTEN_ADDR} ${LISTEN_PORT}
MAXAGE 20
EOF
chmod 0640 /etc/nut/upsd.conf

# upsd.users — reads are anonymous; a user is only needed for SET/commands.
if [ -n "${ADMIN_USER}" ] && [ -n "${ADMIN_PASSWORD}" ]; then
cat > /etc/nut/upsd.users <<EOF
[${ADMIN_USER}]
    password = ${ADMIN_PASSWORD}
    actions = SET
    instcmds = ALL
EOF
else
    : > /etc/nut/upsd.users
fi
chmod 0640 /etc/nut/upsd.users

echo "[entrypoint] starting ${UPS_DRIVER} for [${UPS_NAME}] (${VENDORID}:${PRODUCTID})"
# -u root: container is isolated; avoids USB permission juggling.
/usr/local/sbin/upsdrvctl -u root start

# Give the driver a moment to populate state before upsd answers clients.
sleep 2

echo "[entrypoint] starting upsd on ${LISTEN_ADDR}:${LISTEN_PORT}"
exec /usr/local/sbin/upsd -u root -F
