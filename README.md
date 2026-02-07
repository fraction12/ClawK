# 🦞 ClawK

A native macOS companion app for [OpenClaw](https://github.com/openclaw/openclaw) — your AI agent's mission control.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9+-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## What is ClawK?

ClawK (sounds like "clock" 🕐🦞) is a menu bar app that gives you real-time visibility into your OpenClaw agent — sessions, heartbeats, memory, cron jobs, and more.

## Features

### 🎯 Mission Control
- **Active Sessions** — see all running conversations with token counts and models
- **Active Subagents** — monitor background agent tasks in real-time
- **Heartbeat Monitor** — timeline graph of agent health checks
- **Model Usage** — universal token tracking that works with any AI provider (Claude, GPT, Gemini, etc.)
- **Upcoming Crons** — see scheduled jobs and when they'll fire next
- **Recent Activity** — latest cron run results and durations
- **System Status** — gateway connection, uptime, version info

### 🧠 Memory Browser
- **Context Pressure** — monitor how full your agent's context window is
- **Memory Files** — browse and preview your agent's memory system
- **Archive Health** — track memory tier storage (hot/warm/cold)
- **Curation Schedule** — see when automated memory maintenance runs
- **Memory Activity** — recent memory operations and changes

### ⚙️ Settings
- **Gateway Configuration** — URL, token, connection status
- **Auto-discovery** — finds your OpenClaw installation automatically
- **Setup Wizard** — guided first-run experience

### 📱 Widgets
- Heartbeat status widget
- Active sessions widget
- Context pressure widget
- Memory files widget

## Requirements

- macOS 14.0 (Sonoma) or later
- [OpenClaw](https://github.com/openclaw/openclaw) installed and running

## Installation

### Homebrew (recommended)
```bash
brew install --cask fraction12/tap/clawk
```

### From Source
```bash
git clone https://github.com/fraction12/ClawK.git
cd ClawK
xcodebuild -project ClawK.xcodeproj -scheme ClawK -configuration Release build
```

The built app will be in `build/Build/Products/Release/ClawK.app`. Copy it to `/Applications/`.

### Setup

1. Launch ClawK — it lives in your menu bar (🦞)
2. The setup wizard will auto-detect your OpenClaw installation
3. Paste your gateway token (find it at `~/.openclaw/gateway.token`)
4. You're connected!

## Architecture

```
ClawK/
├── ClawKApp.swift              # App entry point
├── Views/
│   ├── MissionControlView.swift  # Main dashboard
│   ├── Memory/                   # Memory browser views
│   ├── Components/               # Reusable view components
│   └── WelcomeView.swift         # First-run setup wizard
├── ViewModels/                   # View models
├── Services/                     # Gateway client, heartbeat, memory
├── Models/                       # Data models
├── DesignSystem/                 # Design tokens, components
└── Extensions/                   # Swift extensions
```

## How It Works

ClawK connects to your local OpenClaw gateway (default: `http://127.0.0.1:18789`) via its REST API. It polls for session data, cron jobs, and system status at regular intervals.

## Privacy & Data Access

ClawK is designed to be transparent about what it accesses:

- **Gateway API (localhost only)** — All core functionality talks to your local OpenClaw gateway. No data leaves your machine.
- **Claude Quota Tracking (opt-in, Claude users only)** — If you use Claude as your AI provider, the Model Usage card reads Claude Desktop's encrypted cookies from `~/Library/Application Support/Claude/Cookies` to fetch your usage quota from `claude.ai/api`. This data is used solely to display your quota status and is never stored or transmitted elsewhere.
- **CDN Requests (Memory Browser only)** — The Memory Browser's file preview and 3D visualization features load JavaScript libraries from `cdnjs.cloudflare.com` and `cdn.jsdelivr.net` (highlight.js, marked.js, three.js). These are standard open-source CDN-hosted libraries. No user data is sent to these CDNs.

## Contributing

Contributions welcome! Please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE)

## Built by

[Dushyant Garg](https://github.com/fraction12)
