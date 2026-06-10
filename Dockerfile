# syntax=docker/dockerfile:1
#
# Network UPS Tools (NUT) built from source with a patched Phoenixtec/Liebert
# HID subdriver that additionally maps ups.realpower / ups.power /
# ups.realpower.nominal for Salicru SLC TWIN PRO2 (06da:ffff "PPC HID UPS")
# units. Everything else (input/output voltage, frequency, transfer points)
# already works with the stock 0.41 subdriver in NUT >= 2.8.5.
#
# See patches/0001-liebert-hid-salicru-power.patch for the exact change.

ARG NUT_VERSION=2.8.5

# ---------- build stage ----------
FROM debian:bookworm-slim AS build
ARG NUT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config \
        libusb-1.0-0-dev libssl-dev git ca-certificates curl patch \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --branch v${NUT_VERSION} --depth 1 https://github.com/networkupstools/nut.git .

# Apply the Salicru power-mapping patch (fail the build if it does not apply).
COPY patches/0001-liebert-hid-salicru-power.patch /tmp/
RUN git apply --verbose /tmp/0001-liebert-hid-salicru-power.patch \
    && grep -q '0.41-salicru1' drivers/liebert-hid.c

RUN ./autogen.sh \
    && ./configure \
        --prefix=/usr/local \
        --sysconfdir=/etc/nut \
        --with-statepath=/var/run/nut \
        --with-user=root --with-group=root \
        --with-usb=yes \
        --with-drivers=usbhid-ups \
        --without-snmp --without-neon --without-modbus \
        --without-cgi --without-dev --without-doc \
        --disable-static \
    && make -j"$(nproc)" \
    && make install DESTDIR=/staging

# ---------- runtime stage ----------
FROM debian:bookworm-slim
LABEL org.opencontainers.image.title="nuts-patched-salicru" \
      org.opencontainers.image.description="NUT with patched Phoenixtec/Liebert HID subdriver adding realpower/power for Salicru SLC TWIN PRO2 (06da:ffff)" \
      org.opencontainers.image.source="https://github.com/oriolrius/nuts-patched-salicru" \
      org.opencontainers.image.licenses="GPL-2.0-or-later"

RUN apt-get update && apt-get install -y --no-install-recommends \
        libusb-1.0-0 libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /staging/usr/local /usr/local
RUN ldconfig && mkdir -p /var/run/nut /etc/nut

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3493
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD /usr/local/bin/upsc ${UPS_NAME:-ups}@127.0.0.1 ups.status >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
