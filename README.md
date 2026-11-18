# Statuspage Menu Bar

A tiny native macOS menu bar app that shows the live status of the services you depend on — Claude, Kinsta, GitHub, or any status page powered by Atlassian Statuspage — at a glance. Faster than wondering whether *it's me or it's them*, and no more digging through your inbox to see if an incident has been resolved.

[![macOS](https://img.shields.io/badge/macOS-14%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](#)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/robbertvancaem/statuspage-menu-bar?label=release)](https://github.com/robbertvancaem/statuspage-menu-bar/releases)
[![Downloads](https://img.shields.io/github/downloads/robbertvancaem/statuspage-menu-bar/total.svg?label=downloads)](https://github.com/robbertvancaem/statuspage-menu-bar/releases)

## Install

```bash
brew install robbertvancaem/tap/statuspage-menu-bar
open "/Applications/Statuspage Menu Bar.app"
```

No Apple Developer cert, no `xattr` dance — the cask strips the quarantine flag for you on install. Coming from `claude-status-bar`? `brew upgrade` migrates you to the renamed cask.

### Updating

```bash
brew upgrade --cask statuspage-menu-bar
```

### Build from source

```bash
git clone https://github.com/robbertvancaem/statuspage-menu-bar.git
cd statuspage-menu-bar
./build.sh
open "/Applications/Statuspage Menu Bar.app"
```

Needs Xcode Command Line Tools (`xcode-select --install`) and macOS 14+. The build script compiles a universal (arm64 + x86_64) release binary via Swift Package Manager and drops the `.app` bundle into `/Applications/`. Re-running `build.sh` updates the binary in place (ad-hoc signed).

To launch on login: drag `/Applications/Statuspage Menu Bar.app` into **System Settings → General → Login Items**.

## What it does

- Polls every enabled status page every 10 seconds.
- Shows a single icon in the menu bar, reflecting the **worst** status across all enabled services:
  - **Operational** — the symbol of your first service (`sparkles` for Claude), rendered as a template icon that adopts the macOS menu bar theme. Blends in like a native icon when there's nothing to worry about.
  - **Maintenance / Minor / Major / Critical** — the symbol of the affected service (e.g. `server.rack` for Kinsta), colored blue / yellow / orange / red at 50% opacity.
- Click the icon for a section per service: overall status, unresolved incidents (click to open), and components. Services with more than 8 components only list the affected ones.
- Optional native macOS notification on state transitions per service (e.g. "Kinsta: Minor issue").

## Services

Open **Settings…** from the dropdown to pick which status pages to follow.

Built-in presets (Claude is enabled by default):

| Service | Status page |
|---------|-------------|
| Claude | https://status.claude.com |
| Kinsta | https://status.kinsta.com |
| GitHub | https://www.githubstatus.com |
| OpenAI | https://status.openai.com |
| Cloudflare | https://www.cloudflarestatus.com |
| Vercel | https://www.vercel-status.com |
| DigitalOcean | https://status.digitalocean.com |

You can add any other status page by URL, as long as it runs on Atlassian Statuspage (it exposes `/api/v2/summary.json`). The app validates the URL and takes the service name from the page.

## Architecture

A small SwiftUI `MenuBarExtra` app:

| File | Purpose |
|------|---------|
| `Sources/App.swift` | Entry point, menu bar icon, Settings scene |
| `Sources/StatusModel.swift` | Service config + presets, polls Statuspage v2 summaries, aggregates state |
| `Sources/StatusViews.swift` | Dropdown menu and Settings window |
| `build.sh` | Build & install (Swift Package Manager → `.app` bundle) |

The Statuspage v2 API (`/api/v2/summary.json`) is public and unauthenticated, so the app makes plain `URLSession` requests and parses with `Codable`. Enabled services and the notification toggle are persisted in `UserDefaults`.

## Requirements

macOS 14 (Sonoma) or later.

## License

MIT — see [LICENSE](LICENSE).

## Not affiliated

This is an unofficial tool, not affiliated with Anthropic, Kinsta, Atlassian or any of the listed services. All trademarks belong to their respective owners. The app only reads public status pages.
