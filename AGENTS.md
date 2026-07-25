# AGENTS.md

Notes for ZCode agents working in this repository. Read before making changes.

## What this is

GlancePane is a native, menu-bar macOS app (Swift, SwiftUI, AppKit) that turns a small secondary display into a persistent, borderless status dashboard. Apple Silicon only (`arm64`), macOS 14+. Bundle id `dev.danbao.glancepane`. There is no backend — it runs entirely locally and reads metrics from macOS APIs and optional local/remote data sources (Codex app-server, Yahoo Finance, QWeather).

See `README.md`, `PRIVACY.md`, `SECURITY.md`, and `CONTRIBUTING.md` before sensitive changes.

## Build, test, run

This repo does **not** use `swift build`/Xcode project files for normal work. It compiles via `swiftc` invoked from shell scripts under `scripts/`. `Package.swift` exists but the canonical entry points are the scripts.

- `sh scripts/test.sh` — compiles `Sources/GlancePane` (minus `GlancePaneMain.swift`) plus `Tests/GlancePaneTests` with `swiftc` into `.build/tests/GlancePaneTests` and runs it. Tests are a **hand-rolled runner** (`Tests/GlancePaneTests/TestRunner.swift`, `@main GlancePaneTestRunner`), not XCTest. Add new tests as `TestCase(...)` entries there.
- `sh scripts/build.sh` — builds the debug binary to `.build/debug/GlancePane`.
- `sh scripts/package-dmg.sh` — builds release `.app` (via `build-app.sh`), verifies it, and writes `.build/dist/GlancePane-arm64.dmg` + `.sha256`.
- `sh scripts/run-detached.sh` / `sh scripts/restart.sh` / `sh scripts/stop.sh` — run/stop the app detached, writing a pid to `~/.glancepane/glancepane.pid`.
- `sh scripts/logs.sh [--follow|<time>]` — `log show`/`stream` for processes `GlancePane` and `GlancePaneWatchdog`.
- `sh scripts/export-readme-screenshots.sh` — regenerates `docs/screenshots/*.png` from deterministic synthetic fixtures (1280×720).
- `sh scripts/audit-public-tree.sh` — CI guard: scans the public tree for personal data / credential patterns and validates screenshot count + dimensions. Run before pushing.

Tests and screenshots use temporary dirs, synthetic HTTP responses, and offscreen `1280×720` rendering — they never hit live QWeather or Yahoo Finance APIs. Keep that property when adding tests.

## Source layout

- `Sources/GlancePane/GlancePaneMain.swift` — `@main` entry. **Excluded from the test build** (see `test.sh`), so test-runnable code must not live only here.
- `Sources/GlancePane/AppDelegate.swift` — app delegate; owns `DashboardModel`, window, status item, settings, mouse/drag monitors, burn-in logic.
- `Sources/GlancePane/GlancePaneWindow.swift` — `NSWindow` configured `borderless`, `.statusBar` level, `canBecomeKey/Main == false`, click-through.
- `Sources/GlancePane/Models/` — `AppConfig` (Codable config + schema migrations), `DashboardConfiguration`, `SystemSnapshot`/`SystemHistory`, `StockQuote`, `WeatherSnapshot`, `CodexUsage`, `DisplayDescriptor`, `FeedStatus`.
- `Sources/GlancePane/Services/` — app logic: `DashboardModel` (the `@MainActor` `ObservableObject` driving the UI), `ConfigStore` (loads/saves/migrates `~/.glancepane/`), `SecureFileStore` (0700 dirs / 0600 files), `DisplayManager`/`DisplaySelector`, `SystemMetricsService`, `StockService`, `WeatherService`, `Codex*` services, `HealthEvaluator`, `LoginItemService`, `RelaunchPolicy`, `ScreenLockMonitor`, `MouseClickShield`, `HTTPClient` (injectable protocol).
- `Sources/GlancePane/Services/Collectors/` — one collector per metric domain (CPU, GPU, Memory, Storage, Network, Power, Thermal, Host, Process, SMC sensors).
- `Sources/GlancePane/Views/` — SwiftUI pages (`ClockPageView`, `SystemPageView`, `PerformancePageView`, `AgentsPageView`, `MarketPageView`, `WeatherPageView`), `DashboardView`, `DashboardComponents`, `SettingsWindowController`.
- `Sources/GlancePaneWatchdog/` — a tiny embedded helper (plain script, top-level `@main`-free) that relaunches `dev.danbao.glancepane` if it quits, unless `~/.glancepane/suppress-relaunch` matches the current audit session.
- `Resources/` — bundled fonts (Oswald, OFL) and `AppIcon`.
- `docs/` — user-facing docs + `screenshots/` (exactly 6 PNGs at 1280×720).

## Architecture rules

- **Layering**: `Models` → `Services` → `Views`. Views observe `DashboardModel`; services do not import view code. `DashboardModel` is the single `@MainActor` bridge between background services and the SwiftUI views.
- **Dependency injection for tests**: networking and platform access go through protocols (`HTTPClient`, `ThermalCollecting`, `NetworkProbing`, `LoginItemManaging`, …). Keep them injectable so the test runner can substitute fakes — there is no XCTest mock framework in use.
- **Background work**: use `Task`/`Task<Void, Never>` stored on the model, with per-feed **generation counters** (`stockRequestGeneration`, `weatherRequestGeneration`, …) to ignore stale results. Don't block the main thread.
- **Config schema migrations**: `AppConfig.schemaVersion` (currently `7`). On decode, `init(from:)` migrates from older versions and bumps the version; add a new branch and increment `schemaVersion` rather than rewriting stored shapes. Tests cover each migration step — add one when you bump the version.

## Conventions

- **Logging**: `import OSLog`, `Logger(subsystem: "dev.danbao.glancepane", category: …)`. Always annotate interpolated values with `privacy:` — `.public` for non-sensitive operational data, `.private`/`.auto` for anything user-derived (paths, project names, emails). Never log Codex prompts/responses or full project paths.
- **Privacy is load-bearing**: Codex project names are hidden by default; account email, prompts, responses, and full paths are never cached. QWeather JWTs are generated locally and held in memory only. See `PRIVACY.md` — don't weaken these boundaries.
- **File permissions**: write user data via `SecureFileStore` (dirs `0o700`, files `0o600`). Config dir is `~/.glancepane/` (legacy `~/.glancedeck/`, `Application Support/GlanceDeck`, `…/SmartScreen` are migrated on first launch).
- **Display selection**: "Automatic" picks the smallest logical secondary display; configured match is by stable `persistentID`; legacy name match requires a unique exact match (see `DisplaySelector` and its tests).
- **UI changes**: update/keep the deterministic `1280×720` snapshots consistent. Regenerate public images only via `export-readme-screenshots.sh`. README screenshots are synthetic — no real account/network/location data.
- **No secrets in the tree**: `.gitignore` blocks `.env*`, `*.pem`, `*.key`, `*.jwt`, `*.p8`. `audit-public-tree.sh` and Gitleaks enforce this in CI.

## CI

`.github/workflows/build-dmg.yml` runs on macOS 15 / arm64: `test.sh` → `audit-public-tree.sh` → `build.sh` → package arm64 DMG. `gitleaks.yml` scans history. Tests must stay green and off-network.
