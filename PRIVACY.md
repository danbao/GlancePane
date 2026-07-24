# Privacy

GlancePane is a local macOS dashboard. The project does not operate analytics, telemetry, advertising, or account servers.

## Local Data

GlancePane stores its state under `~/.glancepane/`:

- `config.json` contains user-selected settings and service identifiers.
- `stock-cache.json` contains the most recent requested market quotes.
- `weather-cache.json` contains the most recent requested weather response.
- `codex-usage-cache.json` contains account-level token totals and rate-limit windows.

The directory uses POSIX mode `0700`. Configuration, caches, backups, and exported configuration files use mode `0600`.

## Codex

When enabled, the Agents page calls read-only Codex app-server usage endpoints and reads token metadata from local session files. It does not cache prompts, responses, conversation titles, account email, or complete project paths. Project names are hidden by default.

## External Services

- Yahoo Finance receives requests for configured market symbols.
- QWeather receives the configured location and weather requests.

QWeather private keys remain local. GlancePane signs JWTs on-device and caches generated tokens only in memory.

## Screenshots

Repository screenshots are generated from deterministic synthetic fixtures and stripped of EXIF, text, source, and device-profile metadata.
