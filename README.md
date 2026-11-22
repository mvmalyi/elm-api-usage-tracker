# ELM API Tracker

A lightweight, native macOS menu bar app for keeping an eye on your [ELM](https://elm.edina.ac.uk) API spend.

<p align="center">
  <img src="assets/screenshot.jpg" alt="ELM API Tracker" width="460" />
</p>

## Highlights

- **Minimal menu bar gauge** — A monochrome progress ring that blends with macOS light and dark menu bars and stays out of your Dock.
- **At-a-glance usage popover** — Shows spend vs. limit in USD, remaining balance, and a color-coded progress bar (`< 65%` green, `65–85%` amber, `≥ 85%` crimson).
- **Automatic updates** — Refreshes every 5 minutes, on wake from sleep, and whenever you click the icon.
- **Flexible API key setup** — Automatically picks up `ELM_API_KEY` from your environment or shell profile (`~/.zshrc`, `~/.zprofile`, etc.), or paste your key in Settings to store it in macOS Keychain.
- **Launch at Login** — Toggleable directly in Settings.

## Install

Requires **macOS 14 or later** (Universal binary for Apple Silicon & Intel, with Liquid Glass styling on macOS 26+).

1. Download the latest `.dmg` (or `.zip`) from [GitHub Releases](https://github.com/mvmalyi/elm-api-usage-tracker/releases).
2. Drag **ELM API Tracker** into **Applications** and open it.

> **First launch:** Because releases are ad-hoc signed rather than notarized with a paid Apple Developer account, macOS may show a warning the first time you open it. Go to **System Settings → Privacy & Security → Open Anyway**, or run:
> ```bash
> xattr -cr "/Applications/ELM API Tracker.app"
> ```

## Build from Source

```bash
# Build, install to /Applications, and launch
./scripts/build-app.sh --install --open
```

To build a universal `.dmg` and `.zip` package locally:

```bash
./scripts/build-app.sh --universal --version 1.0.0 --package
```

To run the unit tests:

```bash
swift test
```

## Disclosure

Gemini 4 Neon was used in Antigravity to assist with the development of this app. Everything has been tested and security audited. In the case any bugs are discovered, please report them using [GitHub Issues](https://github.com/mvmalyi/elm-api-usage-tracker/issues).
