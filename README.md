# 🦞 ClawK

A native macOS companion app for [OpenClaw](https://github.com/openclaw/openclaw) — your AI agent's mission control.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue) ![Swift](https://img.shields.io/badge/Swift-5.9+-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## What is ClawK?

ClawK (sounds like "clock" 🕐🦞) is a menu bar app that gives you real-time visibility into your OpenClaw agent — sessions, heartbeats, memory, cron jobs, and more.

## Features

### 🎯 Mission Control
- **Active Sessions** — all running conversations with token counts, models, and last activity
- **Active Subagents** — monitor background agent tasks in real-time
- **Heartbeat Monitor** — timeline graph of agent health checks with status history
- **Model Usage** — universal token tracking for any AI provider (Claude, GPT, Gemini, etc.), with Claude-specific quota tracking for Claude users
- **Upcoming Crons** — scheduled jobs and when they fire next
- **Recent Activity** — latest cron run results with durations and status
- **System Status** — gateway connection, uptime, version info

### 🧠 Memory Browser
- **File Browser** — navigate your agent's full memory tree with tiered storage (hot/warm/cold/archive)
- **File Preview** — syntax-highlighted markdown preview with rendered output
- **3D Visualization** — interactive 3D map of your memory embedding space (Three.js)
- **Search** — search across memory files with results highlighting
- **Memory Not Configured** — guided onboarding page if no memory system is detected, explaining setup steps and benefits

### 📊 Memory Vitals
- **Context Pressure** — monitor how full your agent's context window is with visual progress bars
- **Memory Files Status** — file health, size, token counts, and staleness indicators
- **Archive Health** — tier distribution and storage stats across hot/warm/cold/archive
- **Curation Schedule** — tracks automated memory maintenance crons (or shows setup guidance if none configured)
- **Memory Activity** — recent memory searches, writes, and most active files

### 🖼️ Canvas
- **Canvas Status** — see if a canvas is currently presented, its URL, and dimensions
- **Canvas Controls** — present URLs, hide canvas, take snapshots
- **JavaScript Execution** — run JS code directly on the canvas with result display

### ⚙️ Settings
- **Gateway Configuration** — URL, token, connection status with live testing
- **Auto-discovery** — finds your OpenClaw installation automatically
- **Setup Wizard** — guided first-run experience with gateway token input and validation
- **About** — version info, app details

### 💬 Send to ClawK
- **⌘J Message Composer** — send messages directly to your agent session from the menu bar

### 🔗 Connection
- **Connection Status Banner** — persistent banner showing gateway connection state across all views
- **Auto-reconnect** — polls gateway and recovers automatically when connection is restored

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
├── ClawKApp.swift                  # App entry point, lifecycle
├── AppState.swift                  # Global state (sessions, crons, heartbeat, canvas)
├── MenuBar/
│   ├── MenuBarManager.swift        # NSStatusItem, hover popover, window management
│   └── MainWindowView.swift        # Navigation split view, tab routing
├── Views/
│   ├── MissionControlView.swift    # Main dashboard with all status cards
│   ├── CanvasView.swift            # Canvas monitoring and controls
│   ├── SettingsView.swift          # Gateway config, about, setup wizard trigger
│   ├── WelcomeView.swift           # First-run setup wizard (3-step onboarding)
│   ├── ConnectionStatusBanner.swift # Persistent connection state banner
│   ├── SendMessageView.swift       # ⌘J message composer
│   ├── ClawKStatusCard.swift       # Heartbeat monitor with timeline chart
│   ├── ContentView.swift           # Root content view
│   ├── QuickActionsView.swift      # Quick action shortcuts
│   ├── Memory/
│   │   ├── MemoryBrowserView.swift       # File tree browser with tier sections
│   │   ├── MemoryVitalsView.swift        # Memory health dashboard
│   │   ├── MemoryFilePreviewView.swift   # Markdown preview with syntax highlighting
│   │   ├── MemorySearchResultsView.swift # Search results display
│   │   ├── MemoryNotConfiguredView.swift # Onboarding for users without memory system
│   │   ├── MemoryTierComponents.swift    # Tier section UI components
│   │   └── Memory3DVisualizationView.swift # 3D embedding space visualization
│   └── Components/
│       ├── CustomHeartbeatChart.swift    # Timeline chart for heartbeat history
│       ├── ChartData.swift              # Chart data models
│       └── EnhancedQuickStatsView.swift # Stats display components
├── ViewModels/
│   └── MemoryViewModel.swift       # Memory browser state and file loading
├── Services/
│   ├── AppConfiguration.swift      # Auto-discovery, paths, gateway config
│   ├── GatewayClient.swift         # HTTP client for OpenClaw gateway API
│   ├── GatewayConfig.swift         # Token management, gateway URL
│   ├── HeartbeatService.swift      # Heartbeat polling and status tracking
│   ├── HeartbeatHistoryService.swift # Heartbeat timeline history from JSONL
│   ├── MemoryService.swift         # Memory file scanning, tier classification
│   └── QuotaService.swift          # Claude usage quota tracking (optional)
├── Models/
│   ├── SessionInfo.swift           # Session data model
│   ├── CronJob.swift               # Cron job data model
│   ├── HeartbeatModels.swift       # Heartbeat, context pressure, curation models
│   ├── MemoryModels.swift          # Memory file, tier, activity models
│   ├── ModelInfo.swift             # AI model metadata
│   ├── QuotaModels.swift           # Claude quota data models
│   └── CostEstimator.swift         # Token cost estimation
└── DesignSystem/
    ├── Colors.swift                # Color tokens and semantic colors
    ├── Typography.swift            # Font system (.ClawK namespace)
    ├── Spacing.swift               # Spacing tokens and layout constants
    ├── DesignSystem.swift          # View modifiers and shared styles
    └── Components/
        ├── DSCard.swift            # Card container with status variants
        ├── DSHeader.swift          # Page headers with timestamps
        ├── DSStatusBadge.swift     # Connection and status badges
        ├── DSListItem.swift        # Standardized list row components
        ├── DSEmptyState.swift      # Empty state placeholders
        ├── DSSkeleton.swift        # Loading skeleton animations
        └── DSRefreshButton.swift   # Animated refresh button
```

## How It Works

ClawK connects to your local OpenClaw gateway (default: `http://127.0.0.1:18789`) via its REST API. It polls for session data, cron jobs, and system status at regular intervals. The app uses auto-discovery to find your OpenClaw installation — detecting the config file, workspace path, and gateway URL automatically.

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
