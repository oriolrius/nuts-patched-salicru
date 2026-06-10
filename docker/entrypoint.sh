#!/bin/sh
# Generate NUT config from environment, start the USB HID driver and upsd.
# Runs as a NUT *server* (master) that PeaNUT / other hosts connect to.
#
# Optional: SHUTDOWN_ENABLE=true runs upsmon inside the container so that, on a
# critical-battery (OB+LB) event, it powers off the *host* via SHUTDOWN_CMD.
# This is for hosts (e.g. a QNAP) that can't act as a NUT network-slave.
set -eu

UPS_NAME="${UPS_NAME:-ups}"
UPS_DESC="${UPS_DESC:-Salicru SLC TWIN PRO2}"
UPS_DRIVER="${UPS_DRIVER:-usbhid-ups}"
VENDORID="${VENDORID:-06da}"
PRODUCTID="${PRODUCTID:-ffff}"
POLLINTERVAL="${POLLINTERVAL:-2}"
LISTEN_ADDR="${LISTEN_ADDR:-0.0.0.0}"
LISTEN_PORT="${LISTEN_PORT:-3493}"
ADMIN_USER="${ADMIN_USER:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
SHUTDOWN_ENABLE="${SHUTDOWN_ENABLE:-false}"
# Default host-poweroff via nsenter into the host namespaces (needs pid:host +
# privileged). Override for a graceful platform-specific command.
SHUTDOWN_CMD="${SHUTDOWN_CMD:-nsenter -t 1 -m -u -i -n -p -- /sbin/poweroff}"

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

# upsd.users — reads are anonymous. A user is needed for SET/instant-commands
# (PeaNUT) and for upsmon (local or a remote slave) to LOGIN.
if [ -n "${ADMIN_USER}" ] && [ -n "${ADMIN_PASSWORD}" ]; then
cat > /etc/nut/upsd.users <<EOF
[${ADMIN_USER}]
    password = ${ADMIN_PASSWORD}
    actions = SET
    instcmds = ALL
    upsmon master
EOF
else
    : > /etc/nut/upsd.users
fi
chmod 0640 /etc/nut/upsd.users

if [ "${SHUTDOWN_ENABLE}" = "true" ]; then
    [ -n "${ADMIN_USER}" ] && [ -n "${ADMIN_PASSWORD}" ] || {
        echo "[entrypoint] ERROR: SHUTDOWN_ENABLE=true needs ADMIN_USER/ADMIN_PASSWORD" >&2; exit 1; }
    cat > /etc/nut/upsmon.conf <<EOF
RUN_AS_USER root
MONITOR ${UPS_NAME}@localhost 1 ${ADMIN_USER} ${ADMIN_PASSWORD} master
MINSUPPLIES 1
SHUTDOWNCMD "${SHUTDOWN_CMD}"
POWERDOWNFLAG /run/nut/killpower
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
NOCOMMWARNTIME 300
FINALDELAY 5
EOF
    chmod 0640 /etc/nut/upsmon.conf
fi

stop() {
    echo "[entrypoint] stopping"
    [ "${SHUTDOWN_ENABLE}" = "true" ] && /usr/local/sbin/upsmon -c stop 2>/dev/null || true
    /usr/local/sbin/upsd -c stop 2>/dev/null || true
    /usr/local/sbin/upsdrvctl -u root stop 2>/dev/null || true
    exit 0
}
trap stop TERM INT

echo "[entrypoint] starting ${UPS_DRIVER} for [${UPS_NAME}] (${VENDORID}:${PRODUCTID})"
/usr/local/sbin/upsdrvctl -u root start
sleep 2

echo "[entrypoint] starting upsd on ${LISTEN_ADDR}:${LISTEN_PORT}"
/usr/local/sbin/upsd -u root
sleep 2

if [ "${SHUTDOWN_ENABLE}" = "true" ]; then
    echo "[entrypoint] starting upsmon (host shutdown on critical battery): ${SHUTDOWN_CMD}"
    /usr/local/sbin/upsmon
fi

# Supervisor: keep PID 1 alive; exit (→ docker restart) if upsd stops answering.
while true; do
    /usr/local/bin/upsc "${UPS_NAME}"@127.0.0.1 ups.status >/dev/null 2>&1 \
        || { echo "[entrypoint] upsd not responding — exiting for restart"; exit 1; }
    sleep 20 &
    wait $!
done
