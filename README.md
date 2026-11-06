# Lanternfall

A colorful co-op tower-defense game for family and friends. Build a maze of lantern-guardian towers and keep **Pip**, a sleepy living lantern, glowing against waves of mischievous **Snuffers**.

Built with **Godot 4.7** (GDScript) for Windows and macOS, with a dedicated server that runs in Docker.

![Starter towers](art/towers/starter_towers_v2.png)

## Status: Phase 0 (foundations)

- 20 × 12 test board with a Waygate (spawn) and Pip
- Snuffers walk the shortest open path; towers reshape it, and a placement that would seal the path is refused
- Four starter tower models (Pebble Popper, Jelly Lobber, Frost Puff, Hedge Block)
- Server-authoritative multiplayer for up to 8 players (ENet over UDP)
- Username + PIN accounts saved on the server (PINs salted and hashed)
- "Host & play" for testing on one computer, or a dedicated Docker server

Towers don't attack yet; that's Phase 1.

## Play it from the editor

1. Open the project in Godot 4.7.
2. Press **Run** (F5).
3. Type a name and a 4–6 digit PIN, then click **Host & play on this computer**.
4. Pick a tower with **1–4** or the buttons, left-click to place, right-click to remove one of yours.

To test with a second player on your network, have them enter your computer's IP address and click **Join game** (UDP port 7777 must be allowed through the firewall).

## Run the dedicated server (VPS)

On a Linux server with Docker installed:

```bash
git clone https://github.com/thefamilyhub-online/lanterfall.git
cd lanterfall
docker compose -f server/docker-compose.yml up -d --build
docker logs -f lanternfall-server     # should say "listening on UDP 7777"
```

Then open **UDP 7777** in the VPS firewall. Players join with the server's address.

- Accounts and progress are stored in the `lanternfall-data` Docker volume and survive rebuilds.
- To update: `git pull && docker compose -f server/docker-compose.yml up -d --build`.
- Clients and server must run the same game version; the login screen says so if they don't.

## Project layout

| Path | What's there |
| --- | --- |
| `scenes/main.tscn` | Start screen (entry scene) |
| `scripts/net.gd` | Networking: host, join, logins, player list (autoload `Net`) |
| `scripts/accounts.gd` | Server-side accounts and saved progress (autoload `Accounts`) |
| `scripts/world.gd` | The board: path shaping, Snuffers, tower placement |
| `scripts/hud.gd` | In-game HUD |
| `assets/towers/*.glb` | Tower models used by the game (textures baked in) |
| `art/towers/` | Blender source files and renders (ignored by Godot) |
| `server/` | Dockerfile and compose file for the dedicated server |

## Credits

Design and code: the Lanternfall family team. Some future assets may come from the KayKit collections by Kay Lousberg (CC0).
