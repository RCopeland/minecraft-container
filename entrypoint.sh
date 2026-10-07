#!/bin/sh
set -e

# iOS MTU fix: iOS Bedrock clients cannot communicate their effective MTU
# through the Tailscale app, so RakNet MTU discovery fails and iOS clients
# hang at "Locating server". Pin the route MTU to 1280 before starting the
# server. This is best-effort; if the container lacks NET_ADMIN or the
# network setup is unexpected, we warn and continue.

gw=$(ip route show default dev eth0 | awk '{print $3}')
if [ -n "$gw" ] && ip route change default via "$gw" dev eth0 mtu 1280 2>/dev/null; then
    echo "[entrypoint] Changed default route MTU to 1280 on eth0."
else
    echo "[entrypoint] WARNING: Could not set route MTU to 1280 (no default route on eth0 or missing NET_ADMIN?). Continuing anyway."
fi

# Hand off to the image's real entrypoint. /opt/demoter-entry.sh builds the
# entrypoint-demoter argument list from env and then execs it, so the demoter
# still runs as PID 1 and can handle SIGTERM gracefully (including optional
# STOP_SERVER_ANNOUNCE_DELAY support).
exec /opt/demoter-entry.sh
