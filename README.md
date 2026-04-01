# Wypas

Open-source 2D isometric MMORPG platform — play in your browser or download the native client.

## What is Wypas?

Wypas is an open-source MMORPG platform built on protocol 9.63 — the golden era of 2D isometric MMORPGs. It faithfully recreates the depth and charm of classic online worlds while running on modern infrastructure. The game server handles real-time world simulation including creature AI, player combat, quests, housing, guilds, and a player-driven economy.

Players can jump in instantly through any modern browser thanks to a WebAssembly client that runs the same C++ engine as the native desktop version. No downloads, no plugins — just open a tab and play. Native clients with automatic updates are available for macOS and Windows.

The web application includes collaborative map editing with AI-assisted procedural content generation. Creators can build and modify the game world in real-time, while AI tools generate dungeons and terrain using patterns learned from hand-crafted maps.

## Play

### Browser

Visit the website — no download required. Works in Chrome, Firefox, Safari, and Edge.

### Native Client

Download from the [Releases](https://github.com/codefatherllc/wypas/releases) page:

| Platform | Download | Install |
|----------|----------|---------|
| macOS | [DMG](https://github.com/codefatherllc/wypas/releases/latest/download/wypas-setup.dmg) | Open DMG, drag Wypas to Applications |
| Windows | [Installer](https://github.com/codefatherllc/wypas/releases/latest/download/wypas-setup.exe) | Run the installer |
| Linux | [AppImage](https://github.com/codefatherllc/wypas/releases/latest/download/wypas.AppImage) | `chmod +x wypas.AppImage && ./wypas.AppImage` |

The native client updates itself automatically.

## Architecture

```
                  ┌───────────────────────┐
                  │       Players         │
                  │  Browser    Native    │
                  └─────┬──────────┬─────┘
                        │          │
                  ┌─────▼──────────▼─────┐
                  │    Envoy (HTTPS)      │
                  └──────────┬───────────┘
                             │
          ┌──────────┬───────┼───────┬──────────┐
          │          │       │       │          │
     ┌────▼───┐ ┌───▼──┐ ┌──▼──┐ ┌──▼───┐ ┌───▼────┐
     │  Auth  │ │  API │ │ Web │ │Assets│ │Creator │
     └────────┘ └──────┘ └─────┘ └──────┘ └───┬────┘
                                               │
                                        ┌──────┼──────┐
                                        │      │      │
                                   ┌────▼─┐ ┌──▼──┐ ┌─▼──────┐
                                   │Brain │ │ GPU │ │Database│
                                   └──────┘ └─────┘ └────────┘

     Game Server (:7172 TCP, :7173 WS) — direct, not proxied
     Status (:7171 TCP) — direct
     Brain MCP (:3001 SSE) — direct
```

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| **Game Server** | C++ 17 | Real-time world simulation — creatures, combat, quests, economy |
| **Game Client** | C++ / WASM | Native desktop (macOS, Windows) + browser via WebAssembly |
| **Auth** | Go | Account management, login, JWT tokens |
| **API** | Go | REST endpoints + WebSocket hub (online count, live activity) |
| **Web App** | Vue 3 / TS | Frontend SPA — accounts, highscores, community, map editor |
| **Creator** | Go | Map editing backend with real-time collaboration via WebSocket |
| **Brain** | Go + ONNX | Procedural map generation — dungeons and terrain from learned patterns |
| **Graphics** | Rust (GPU) | Sprite filtering and visual effects via Metal/Vulkan |
| **Core** | C++ 17 | Shared pathfinding, tile logic, map validation |
| **Shared Lib** | Go | Common packages — auth, database, sprites, taxonomy |

## Deployment

Hybrid Docker + native architecture. Go services run in Docker (linux/arm64+amd64). Server, brain, and graphics run natively on macOS for Metal GPU access. Orchestrated by [wypas-proxy](https://github.com/codefatherllc/wypas-proxy).

```bash
# Local dev (Docker + Make + Git)
git clone git@github.com:codefatherllc/wypas-proxy.git && cd wypas-proxy
make login && make dev

# Production
make prod  # Docker services + native processes + launchd
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Game Server | C++ 17 |
| Game Client | C++ 17 / Emscripten (WebAssembly) |
| Backend Services | Go |
| Frontend | Vue 3 / TypeScript |
| Sprite Processing | Rust (wgpu / Metal) |
| AI / ML | PyTorch (training) → ONNX Runtime (inference) |
| Database | MariaDB |
| Deployment | Docker + Envoy + native (macOS) |

## License

Each component is licensed independently — see individual repository LICENSE files.
