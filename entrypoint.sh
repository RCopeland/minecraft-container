#!/bin/sh
set -e

# Hand off to the image's real entrypoint. /opt/demoter-entry.sh builds the
# entrypoint-demoter argument list from env and then execs it, so the demoter
# still runs as PID 1 and can handle SIGTERM gracefully (including optional
# STOP_SERVER_ANNOUNCE_DELAY support).
#
# NOTE: the iOS MTU fix does NOT live here. The Bedrock image ships no
# networking tools (no `ip`, `ifconfig`, or busybox), so the MTU is set from
# the Tailscale sidecar instead -- see sidecar-entrypoint.sh.
exec /opt/demoter-entry.sh
