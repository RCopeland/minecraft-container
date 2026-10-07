#!/bin/sh
set -e

# iOS MTU fix. iOS Bedrock clients cannot communicate their effective MTU
# through the Tailscale app, so RakNet MTU discovery fails and iOS clients hang
# at "Locating server" while Windows clients connect fine
# (see itzg/docker-minecraft-bedrock-server discussion #553).
#
# This runs in the TAILSCALE sidecar, not the Bedrock container: the sidecar
# owns the shared network namespace and is the only image here that ships
# `ip` (the Bedrock image is Debian with no networking tools at all). Because
# the Bedrock container shares this netns via `network_mode: service:tailscale`,
# setting the device MTU here applies to both.
#
# Best-effort: never block startup if the interface is not up yet.

IFACE="${MTU_INTERFACE:-eth0}"
MTU="${MTU_VALUE:-1280}"

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -e "/sys/class/net/${IFACE}" ]; then break; fi
    sleep 1
done

if ip link set dev "$IFACE" mtu "$MTU" 2>/dev/null; then
    echo "[entrypoint] Set ${IFACE} MTU to ${MTU} (iOS RakNet MTU discovery fix)."
else
    echo "[entrypoint] WARNING: Could not set ${IFACE} MTU to ${MTU}; continuing anyway."
fi

# Hand off to the image's real entrypoint (containerboot), which brings up
# tailscaled and blocks for the lifetime of the container.
exec /usr/local/bin/containerboot
