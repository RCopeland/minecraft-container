# Minecraft Bedrock on the homelab

A self-hosted [Minecraft Bedrock Dedicated Server](https://www.minecraft.net/en-us/download/server/bedrock)
reachable **only over the tailnet**, using the same tailscale-sidecar pattern as
`~/Dev/kavita-container`, `~/Dev/storyteller-container`, `~/Dev/yamtrack-container`,
`~/Dev/romm`, and `~/Dev/n8n`. No funnel, no published host ports.

> **Status:** scaffolding in progress. The compose stack, `ts-serve.json`, and
> setup docs are being added next.

## Why Bedrock (and why no funnel)

Bedrock Edition is the edition that runs on **iPads and Windows PC**, and those
two cross-play on the same server. Java Edition cannot be joined by an iPad, and
Tailscale Funnel cannot carry a Minecraft server regardless of edition:

- Funnel only listens on ports `443`, `8443`, and `10000`, is TLS-only, and has
  no UDP support at all.
- Bedrock speaks RakNet over **UDP 19132**, so it is not Funnel-able.

The tailnet-only pattern used by the rest of this homelab is therefore the right
fit — and the safer choice for kids' devices.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml` | tailscale sidecar + Bedrock server |
| `ts-serve.json` | `tailscale serve` config (tailnet-only) |
| `entrypoint.sh` | MTU fix for iOS clients, then start the server |
| `.env` / `.env.example` | secrets/config |
