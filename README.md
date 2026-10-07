# Minecraft Bedrock on the homelab

A self-hosted [Minecraft Bedrock Dedicated Server](https://www.minecraft.net/en-us/download/server/bedrock)
for **iPads and Windows PCs on the home LAN**, running on port `19132`.

> **Tailnet-only was investigated and rejected.** See
> [Why this runs on the host network](#why-this-runs-on-the-host-network) — the
> short version is that Tailscale cannot carry a Bedrock server in this homelab's
> current configuration, and the intended clients (the kids' iPads) are at home
> anyway.

## Why Bedrock

Bedrock Edition is the edition that runs on **iPads and Windows PC**, and those
two cross-play on the same server. Java Edition cannot be joined by an iPad.

## Why this runs on the host network

This stack deliberately does **not** use the tailscale-sidecar pattern that
`kavita-container`, `romm`, `n8n-container` and the others use. Two independent
problems make that pattern unusable here:

**1. Tailscale cannot proxy UDP.** Every other stack in this homelab is an HTTP
app, reached through `tailscale serve`, which is an HTTP/TCP reverse proxy. It
has no UDP support (and `funnel` is TLS/SNI-based, so UDP is out there too).
Bedrock is pure RakNet over UDP 19132, so there is no proxy path for it.

**2. This homelab has no `/dev/net/tun`.** Without that device node Tailscale
runs in `tun=userspace-networking` mode, where it forwards inbound tailnet
traffic to `localhost` *within its own process tree*. A UDP socket owned by a
different container is not reachable that way. Verified directly:

```text
sidecar listening on 19132, reached over tailnet   -> received
app container listening on 19132, over tailnet     -> 0 bytes
app container on 127.0.0.1:19132                   -> 148-byte RakNet pong
```

So the server runs on the **host network** instead. It binds the host's normal
interfaces and any device on the home wifi reaches it directly. If remote access
is ever wanted, the correct fix is a real TUN device on the host so Tailscale
leaves userspace mode — **not** a published port and **not** a funnel.

## How it works

- `bedrock` runs with `network_mode: host`, so it binds the host's interfaces
  directly on UDP `19132`.
- `entrypoint.sh` preserves the image's graceful-shutdown entrypoint, so
  `docker compose stop` saves the world cleanly rather than killing it.
- `TRANSPORT=raknet` is forced. See [Troubleshooting](#troubleshooting) for why
  this matters — it is the single most important setting here.
- No web UI. Bedrock has none; there is no `ts-serve.json` in this repo.

## Run

Fill `.env` if you have not already, then:

```bash
docker compose up -d
docker compose logs -f bedrock
```

Wait for `Server started.` then confirm it is listening on UDP 19132.

## Connecting

The server address is **the homelab's LAN IP on port `19132`**:

```text
192.168.4.37:19132
```

That is the current address of this host. If its DHCP lease ever changes you
will need to update the server entry on each device — consider a DHCP
reservation for the homelab.

### From an iPad (primary use case)

1. Make sure the iPad is on the home wifi.
2. Open Minecraft → **Play** → **Servers** → scroll down → **Add Server**.
3. Server Address: `192.168.4.37`, Port: `19132`.
4. Save, then join.
5. Each player signs in with their Xbox Live / Microsoft account (the family
   accounts already set up for the kids).

**No Tailscale is needed on the iPads.** They are on the same LAN, so ordinary
local networking is enough.

### From a Windows PC

Identical steps: Windows uses the same Bedrock Edition and cross-plays with the
iPads. Bedrock also auto-discovers LAN games, so the server may appear in the
**Friends** tab without adding it manually.

## Configuration

All game settings are environment variables in `.env`.

| Variable | Purpose | Default |
|----------|---------|---------|
| `EULA` | Accept the Mojang EULA (`TRUE` required) | `TRUE` |
| `SERVER_NAME` | Name shown in the server list | `Copeland Family Minecraft` |
| `GAMEMODE` | `survival`, `creative`, `adventure` | `survival` |
| `DIFFICULTY` | `peaceful`, `easy`, `normal`, `hard` | `normal` |
| `ALLOW_CHEATS` | Enable commands/cheats | `false` |
| `ONLINE_MODE` | Require Xbox Live auth | `true` |
| `TRANSPORT` | **Must stay `raknet`** — see Troubleshooting | `raknet` |
| `ALLOW_LIST` | Strict per-player allowlist | `false` |
| `TZ` | Timezone | `America/New_York` |

World data, configs and backups live in the named volume `minecraft_data`
mounted at `/data`.

## Troubleshooting

### Clients cannot connect even though the server looks healthy

**Check `transport` first.** Mojang changed the default transport to
**NetherNet** in Bedrock 1.26.50+, and it is broken:

> `transport=nethernet` renders server inaccessible … the server is **visible,
> but not accessible**. Attempting to connect to the server times out with the
> “door” error.
> — [BDS-23108](https://mojira.dev/BDS-23108)

The symptom is nasty because the server looks fine: it logs
`Accepting clients on [::]:19132` while **nothing is actually bound to 19132**.

This repo forces `TRANSPORT=raknet`. Verify:

```bash
docker exec minecraft-bedrock grep '^transport=' /data/server.properties
# expect: transport=raknet

# confirm the UDP socket really exists (0x4ABC == 19132)
docker exec minecraft-bedrock grep -i 4abc /proc/net/udp
```

You may see a `TRANSPORT TYPE ERROR` warning saying NetherNet is "the only
supported transport type". That warning is expected and safe to ignore —
`raknet` still works and is what clients need.

### Server is up but not reachable from the LAN

```bash
ss -lunp | grep 19132           # on the homelab
docker compose logs bedrock | tail -20
```

Also confirm the client is on the same network and that the LAN IP has not
changed.

### Players are locked out / "allow list" warnings

The Bedrock image defaults `allow-list=true` with an empty list, which blocks
everyone. This repo sets `ALLOW_LIST=false` so a fresh volume cannot
reintroduce it. Access control comes from `ONLINE_MODE` instead. To restrict to
specific players, set `ALLOW_LIST=true` and add entries to
`/data/allowlist.json` in the `minecraft_data` volume.

### After a Minecraft update, clients suddenly cannot join

Bedrock auto-updates on the client but not the server. Restart to pull the new
server build:

```bash
docker compose restart bedrock
```

## Security notes

- Online mode is on, so players authenticate against Xbox Live and cannot spoof
  names or join anonymously.
- There is **no allowlist** (deliberate). Anyone on the home LAN with a valid
  Xbox Live account can join.
- The server is reachable from the home LAN only. It is not exposed to the
  internet, and it is not on the tailnet. Do **not** add port forwards or a
  funnel.
- No secrets are stored in this repo. `.env` is git-ignored.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml` | Bedrock server on the host network |
| `entrypoint.sh` | preserves the image's graceful-shutdown entrypoint |
| `.env` / `.env.example` | game configuration (`.env` is git-ignored) |
