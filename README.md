# Minecraft Bedrock on the homelab

Self-hosted Minecraft Bedrock Dedicated Server — the edition that runs on
**iPads and Windows PCs** (cross-play) — reachable **only over the tailnet**
using the same tailscale-sidecar pattern as `~/Dev/kavita-container`,
`~/Dev/storyteller-container`, `~/Dev/yamtrack-container`, `~/Dev/romm`, and
`~/Dev/n8n`. No funnel, no published host ports — the server is available only
to devices on the tailnet.

## Why Bedrock (and why no funnel)

Bedrock Edition is the edition that runs on **iPads and Windows PC**, and those
two cross-play on the same server. Java Edition cannot be joined by an iPad, and
Tailscale Funnel cannot carry a Minecraft server regardless of edition:

- Funnel only listens on ports `443`, `8443`, and `10000`, is TLS-only, and has
  no UDP support at all.
- Bedrock speaks RakNet over **UDP 19132**, so it is not Funnel-able.

The tailnet-only pattern used by the rest of this homelab is therefore the right
fit — and the safer choice for kids' devices.

## How it works

- A **tailscale sidecar** joins the tailnet as host `minecraft`. It does **not**
  run `tailscale serve` — this stack is pure UDP, and Tailscale carries RakNet
  traffic natively inside the tailnet. No `AllowFunnel`, no HTTPS handlers.
- **`bedrock`** shares the sidecar's namespace
  (`network_mode: service:tailscale`). It is not published on the host, so
  nothing on the LAN or internet can reach it.
- An **`entrypoint.sh`** wrapper runs before the server to apply an iOS MTU fix
  (see [Troubleshooting iOS clients](#troubleshooting-ios-clients)). The script
  pins the default route MTU to 1280; if it can't, it warns and continues.

## Run

Fill `.env` (`TAILSCALE_AUTH_KEY`) if you haven't, then:

```bash
docker compose up -d
docker compose logs -f bedrock
```

Verify over the tailnet:

```bash
tailscale status | grep minecraft
```

## First-time setup

1. Bring the stack up (`docker compose up -d`).
2. Watch the logs (`docker compose logs -f bedrock`) until you see the server
   listening on UDP 19132.
3. The server is now reachable at the tailnet IP of the `minecraft` node and
   (for most clients) at `minecraft.<your-tailnet>.ts.net`.

## Connecting from an iPad

> **Use the tailnet IP, not the MagicDNS hostname.** Open iOS Tailscale has
> unresolved MagicDNS bugs
> ([tailscale/tailscale#18385](https://github.com/tailscale/tailscale/issues/18385),
> [#13799](https://github.com/tailscale/tailscale/issues/13799)) where in-app
> hostname resolution fails unless an exit node is configured. Use the server's
> 100.x.y.z Tailscale IP directly.

1. Open the Minecraft app.
2. Tap **Play** → **Servers** → **Add Server**.
3. Enter the server's 100.x.y.z tailnet IP and port **19132**.
4. Tap **Save** and join.
5. Players must sign in with their Xbox Live / Microsoft account (family accounts
   already set up for the kids).

## Connecting from a PC

1. Open Minecraft Bedrock Edition (via Windows Store/Xbox app).
2. Click **Play** → **Servers** → **Add Server**.
3. Enter `minecraft.<your-tailnet>.ts.net` (MagicDNS) or the 100.x.y.z tailnet
   IP, port **19132**.
4. Click **Save** and join.
5. Sign in with the same Xbox Live / Microsoft account used on the iPad.

## Configuration

All game settings are controlled via environment variables in `.env`.

| Variable | Purpose | Default |
|----------|---------|---------|
| `TAILSCALE_AUTH_KEY` | Tailscale node auth key (required) | (none) |
| `EULA` | Accept the Mojang EULA (`TRUE` required) | `TRUE` |
| `SERVER_NAME` | Name shown in the server list | `Copeland Family Minecraft` |
| `GAMEMODE` | Default game mode (`survival`, `creative`, `adventure`) | `survival` |
| `DIFFICULTY` | World difficulty (`peaceful`, `easy`, `normal`, `hard`) | `normal` |
| `ALLOW_CHEATS` | Enable commands/cheats (`true`/`false`) | `false` |
| `ONLINE_MODE` | Require Xbox Live auth (`true`/`false`) | `true` |
| `TZ` | Timezone | `America/New_York` |

World data, configs, and backups live in the named volume `minecraft_data`
mounted at `/data`.

## Troubleshooting iOS clients

**"Locating server" hangs indefinitely**

iOS Bedrock clients cannot communicate their effective MTU through the Tailscale
app, so RakNet MTU discovery fails and the client hangs at "Locating server"
while Windows clients connect fine. See
[itzg/docker-minecraft-bedrock-server#553](https://github.com/itzg/docker-minecraft-bedrock-server/discussions/553).

The `entrypoint.sh` wrapper attempts to pin the route MTU to 1280 before
starting the server. If the container lacks `NET_ADMIN` (it is granted in
`compose.yaml`) or the route command otherwise fails, the script logs a warning
and continues — the container will not crash, but iOS clients may still hang.

**Fix:** Verify the container has `cap_add: [NET_ADMIN]` and the route command
succeeded in the logs.

**MagicDNS hostname does not resolve on iOS**

As noted in [Connecting from an iPad](#connecting-from-an-ipad), open iOS
Tailscale has bugs that break MagicDNS resolution in the Minecraft app unless an
exit node is active. Use the raw 100.x.y.z tailnet IP instead.

## Security notes

- The instance is intentionally **not** exposed to the LAN or internet; it's
  safe behind the tailnet. Do **not** add published ports or funnel access.
- The only secret is `TAILSCALE_AUTH_KEY` in `.env` (git-ignored). Rotate it in
  the Tailscale admin console if it ever leaks.
- `ONLINE_MODE=true` requires real Xbox Live accounts, so players can't spoof
  names or join anonymously.
- No whitelist is configured (declined by user) — anyone on the tailnet with a
  valid Xbox Live account can join.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml` | tailscale sidecar + Bedrock server |
| `entrypoint.sh` | MTU fix for iOS clients, then starts the server |
| `.env` / `.env.example` | secrets/config (`.env` is git-ignored) |
