# Minecraft on the homelab

A **Java Edition server with Bedrock crossplay**, so the iPads and a Java PC share
one world. Reachable from the home LAN.

```
Java clients    ->  192.168.4.37:25565     (you: Java 26.3)
Bedrock clients ->  192.168.4.37:19132     (the kids' iPads, Windows Bedrock)
```

| Component | Role |
|-----------|------|
| **Paper** 26.2 | The Java server itself |
| **Geyser** | Translates Bedrock ↔ Java so iPads can join |
| **Floodgate** | Lets Bedrock players join **without** owning Java accounts |
| **ViaVersion** + **ViaBackwards** | Lets a newer Java client (26.3) join this 26.2 server |

## Why Java + Geyser rather than a Bedrock server

Java and Bedrock are separate games with incompatible protocols, and **a Java
client can never connect to a Bedrock server**. Geyser only bridges one
direction — Bedrock clients joining a Java server — so the Java server is the
hub and the iPads come in through Geyser.

The earlier Bedrock-only setup worked for the iPads but shut out Java entirely,
which is why this was rebuilt.

## Why 26.2 and not 26.3

The Java client is 26.3, but the server runs **26.2**, deliberately:

- **Geyser emulates a Java 26.2 client.** On a 26.3 server it needs ViaVersion
  *and* ViaBackwards bolted on, which the Geyser project documents as the
  fragile path.
- **Paper 26.3 is still BETA** (build 159); 26.2 build 132 is the current
  **STABLE** release.

ViaVersion makes the 26.3 client work against the 26.2 server, which is the
supported way to do this. Revisit once Geyser and Paper ship stable 26.3.

## Why this runs on the host network

Deliberately **not** the tailscale-sidecar pattern used by `kavita-container`,
`romm`, `n8n-container` and the rest. That pattern cannot carry Minecraft traffic
on this homelab, for two independent reasons:

**1. This homelab has no `/dev/net/tun`.** Without it Tailscale runs in
`tun=userspace-networking` mode, which forwards inbound tailnet traffic to
`localhost` *within its own process tree*, so a socket owned by a different
container is unreachable. Verified directly — the sidecar could receive tailnet
UDP on any port, the app container never could, while the same port answered
fine on `127.0.0.1`.

**2. `tailscale serve` is HTTP/TCP only.** It cannot carry Minecraft's traffic,
and `funnel` is TLS/SNI-based so it is not an option either.

On the host network the server binds the host's normal interfaces, so LAN devices
reach it directly. Intended access is the home wifi, so **the kids' iPads need no
Tailscale at all**.

If remote access is ever wanted the correct fix is a real TUN device on the host
so Tailscale leaves userspace mode — **not** a published port and **not** a funnel.

## Run

```bash
cp .env.example .env     # already done on the homelab
docker compose up -d
docker compose logs -f minecraft
```

First boot takes a few minutes: it downloads Paper, the plugins, then generates
the world. Wait for `Done (...)! For help, type "help"`.

Verify both paths:

```bash
# Bedrock path (expect a RakNet response, not zero bytes)
printf '01000000000000000000ffff00fefefefefdfdfdfd123456780000000000000000' \
  | xxd -r -p | timeout 5 nc -u 192.168.4.37 19132 | wc -c

# Java path
nc -z 192.168.4.37 25565 && echo "java port open"
```

## Connecting

### From an iPad (Bedrock)

1. iPad on the home wifi.
2. Minecraft → **Play** → **Servers** → scroll down → **Add Server**.
3. Address `192.168.4.37`, port `19132`.
4. Join. Floodgate means **no Java account is needed** — the existing Xbox Live
   family accounts are enough.

### From a Java client

1. Add a server: `192.168.4.37:25565`.
2. A 26.3 client connects fine — ViaVersion translates it to the server's 26.2.
3. You will be asked to authenticate with your Mojang/Microsoft account
   (`ONLINE_MODE=true`).

## Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `EULA` | Accept the Mojang EULA (`TRUE` required) | `TRUE` |
| `MINECRAFT_VERSION` | Server version — **leave at 26.2** | `26.2` |
| `SERVER_NAME` | Name shown in the server list | `Copeland Family Minecraft` |
| `MOTD` | Message shown under the name | see `.env.example` |
| `GAMEMODE` | `survival`, `creative`, `adventure` | `survival` |
| `DIFFICULTY` | `peaceful`, `easy`, `normal`, `hard` | `normal` |
| `ALLOW_CHEATS` | Enable command blocks | `false` |
| `VIEW_DISTANCE` | Chunk view distance | `10` |
| `MAX_PLAYERS` | Player cap | `10` |
| `ONLINE_MODE` | Require authentication | `true` |
| `MEMORY` | JVM heap for the server | `3G` |
| `GEYSER_PORT` | Bedrock UDP port | `19132` |
| `TZ` | Timezone | `America/New_York` |

World data lives in the named volume `minecraft-container_java_data` at `/data`.

## Troubleshooting

### Container crash-loops with "Failed to download paper"

Known issue: the itzg image's Paper installer still calls `api.papermc.io`,
which PaperMC sunset (it now returns HTTP 410).

This repo works around it by using `TYPE=CUSTOM` with a direct URL to the stable
26.2 jar, instead of `TYPE=PAPER`. Switch back once the image tracks the new
`fill.papermc.io` API.

To upgrade the server jar:

```bash
docker compose stop
docker run --rm -v minecraft-container_java_data:/data alpine rm -f /data/paper-*.jar
# update CUSTOM_SERVER in compose.yaml to the new jar URL, then:
docker compose up -d
```

### "MODRINTH_LOADER must be set" or "No files are available for ... loader paper"

`TYPE=CUSTOM` gives the image no game version, so plugin lookups fail. Both
`VERSION=26.2` and `MODRINTH_LOADER=paper` are required and already set.

Separately: **Geyser and Floodgate are not installable from Modrinth.** The
Modrinth `floodgate` project is *Floodgate-Modded*, a Fabric/NeoForge port with
no Paper build. Both come from GeyserMC's own download service via `PLUGINS`.
ViaVersion and ViaBackwards do publish a paper loader, so they use Modrinth.

### A Bedrock client cannot join

Check Geyser is listening and the plugin loaded:

```bash
ss -lun | grep 19132
docker compose logs minecraft | grep -i geyser | tail -20
```

Geyser supports Bedrock **26.30–26.52**. A significantly older Bedrock client
will be refused; update the game on the device.

### A Java client cannot join

`ONLINE_MODE=true` means a real Mojang/Microsoft login is required. Check the
client is on 26.3 or older (ViaVersion handles newer clients joining an older
server, not the reverse without ViaBackwards).

### After a Minecraft update

Wait for Paper *and* Geyser to ship stable builds before raising
`MINECRAFT_VERSION`. Raising it early puts you on beta server software and may
break the Bedrock bridge.

## Backups

The world is in the `minecraft-container_java_data` volume:

```bash
docker run --rm -v minecraft-container_java_data:/data -v "$PWD:/backup" \
  alpine tar czf /backup/world-$(date +%F).tar.gz -C /data world
```

## Security notes

- Reachable from the **home LAN only**. Not exposed to the internet, and not on
  the tailnet. Do **not** add port forwards or a funnel.
- `ONLINE_MODE=true`: Java players authenticate normally; Bedrock players go
  through Floodgate, which trusts Xbox Live identities.
- No allowlist is configured, so anyone on the home wifi with a valid account
  can join. Add one if that becomes a problem.
- RCON listens on `25575` inside the container. It is bound on the host network,
  so treat it as LAN-visible; change or disable `ENABLE_RCON` if that matters.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml` | Paper + Geyser server on the host network |
| `.env` / `.env.example` | server configuration (`.env` is git-ignored) |
