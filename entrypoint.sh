#!/bin/sh
set -e

# iOS MTU fix: iOS Bedrock clients cannot communicate their effective MTU
# through the Tailscale app, so RakNet MTU discovery fails and iOS clients
# hang at "Locating server". Pin the route MTU to 1280 before starting the
# server. This is best-effort; if the container lacks NET_ADMIN or the
# network setup is unexpected, we warn and continue.

if ip route change default dev eth0 mtu 1280 2>/dev/null; then
    echo "[entrypoint] Changed default route MTU to 1280 on eth0."
else
    if ip route add default dev eth0 mtu 1280 2>/dev/null; then
        echo "[entrypoint] Added default route with MTU 1280 on eth0."
    else
        echo "[entrypoint] WARNING: Could not set route MTU to 1280 (missing NET_ADMIN or no default route on eth0?). Continuing anyway."
    fi
fi

# Hand off to the image's real entrypoint. `exec` replaces this shell so the
# demoter runs as PID 1 and can handle SIGTERM gracefully.
exec /usr/local/bin/entrypoint-demoter --match /data --debug --stdin-on-term stop /opt/bedrock-entry.sh
