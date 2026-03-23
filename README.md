# Wypas

Open-source 2D isometric MMORPG platform — play in your browser or download the native client.

## What is Wypas?

Wypas is an open-source MMORPG platform that brings classic 2D isometric gameplay to modern technology. Built on protocol 9.63 — widely regarded as the golden era of 2D MMORPGs — it faithfully recreates the depth and charm of old-school online worlds while running on today's infrastructure. The game server handles real-time world simulation including creature AI, player combat, quests, housing, guilds, and a full player-driven economy.

What makes Wypas unique is its accessibility. Players can jump in instantly through any modern browser thanks to a WebAssembly client that runs the same C++ engine as the native desktop version. No downloads, no plugins — just open a tab and play. For those who prefer a traditional experience, native clients are available for macOS, Windows, and Linux with automatic updates.

Beyond the game itself, Wypas includes a web-based map editor with AI-assisted procedural content generation. Creators can build and modify the game world collaboratively in real-time, while AI tools generate dungeons and terrain using patterns learned from hand-crafted maps. The entire platform is built by the community, for the community.

## Screenshots

<!-- Screenshots coming soon -->

## Architecture

```
                    ┌───────────────────────┐
                    │       Players         │
                    │  Browser    Native    │
                    └─────┬──────────┬─────┘
                          │          │
                    ┌─────▼──────────▼─────┐
                    │    Web Gateway        │
                    │  (TLS termination,    │
                    │   routing)            │
                    └──────────┬───────────┘
                               │
            ┌──────────┬───────┼───────┬──────────┐
            │          │       │       │          │
       ┌────▼───┐ ┌───▼──┐ ┌──▼──┐ ┌──▼───┐ ┌───▼────┐
       │  Auth  │ │  API │ │ Web │ │Assets│ │ Game   │
       │Service │ │      │ │ App │ │      │ │Server  │
       └────────┘ └──────┘ └─────┘ └──────┘ └───┬────┘
                                                  │
                                            ┌─────▼─────┐
                                            │ Database  │
                                            └───────────┘

       ┌─────────────────────────────────────────┐
       │           Content Tools                  │
       │                                          │
       │  Visual Map Editor    AI Map Generator   │
       │  Sprite Processing    Data Management    │
       └─────────────────────────────────────────┘
```

## Components

| Component | Language | Description |
|-----------|----------|-------------|
| **Game Server** | C++ 17 | Real-time world simulation — creatures, combat, quests, economy |
| **Game Client** | C++ / WebAssembly | Cross-platform — native desktop + browser |
| **Authentication** | Go | Account management, secure login, session tokens |
| **REST API** | Go | Game data endpoints + real-time WebSocket communication |
| **Web Application** | Vue 3 / TypeScript | Browser frontend — accounts, highscores, community |
| **Map Editor** | Go + Vue 3 | Web-based collaborative map editing with live preview |
| **AI Content Generator** | Go + ONNX | Procedural dungeons and terrain from learned patterns |
| **Sprite Tools** | Rust (GPU) | Real-time sprite filtering and visual effects processing |
| **Core Library** | C++ 17 | Shared pathfinding, tile logic, and map validation |
| **Shared Utilities** | Go | Common packages — auth, database, configuration |

## How It Works

Players connect via browser or native client. The web gateway handles TLS termination and routes traffic to the appropriate service. The game server simulates the world in real-time — creatures move, combat resolves, quests progress, and the economy runs. Graphics and map data are cached locally with automatic updates so returning players load in fast.

The map editor lets creators build and modify the game world collaboratively through a browser-based interface. AI tools can generate new dungeons and terrain using patterns learned from hand-crafted maps, giving creators a head start on new content.

## Play

### Browser

Visit the website — no download required. Works in Chrome, Firefox, Safari, and Edge.

### Native Client

Download the latest release for your platform from the [Releases](https://github.com/codefatherllc/wypas/releases) page.

| Platform | Download | Install |
|----------|----------|---------|
| macOS | [DMG](https://github.com/codefatherllc/wypas/releases/latest/download/wypas-macos.dmg) | Open the DMG, drag to Applications |
| Windows | [Installer](https://github.com/codefatherllc/wypas/releases/latest/download/wypas-setup.exe) | Run the installer |
| Linux | [AppImage](https://github.com/codefatherllc/wypas/releases/latest/download/wypas-linux.AppImage) | `chmod +x wypas-linux.AppImage && ./wypas-linux.AppImage` |

> The native client automatically updates itself when new versions are available.

## For Developers

Each component lives in its own repository with independent build instructions, CI pipelines, and release cycles. The game server is built on [The Forgotten Server](https://github.com/otland/forgottenserver) — the long-running open-source MMORPG server project — extended with WebSocket support, performance optimizations, and modern C++ practices.

The protocol is 9.63, a classic 2D isometric MMORPG protocol. The WebAssembly client compiles the same C++ codebase to run natively in the browser with full feature parity.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Game Server | C++ 17 |
| Game Client | C++ 17 / Emscripten (WebAssembly) |
| Backend Services | Go |
| Frontend | Vue 3 / TypeScript |
| Sprite Processing | Rust (GPU compute) |
| AI / ML | ONNX Runtime |
| Database | MariaDB |
| Deployment | Docker containers + reverse proxy |

## License

Each component is licensed independently — see individual repository LICENSE files for details.
