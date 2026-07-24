# Contributing

Contributions are welcome.

1. Create a branch from `main`.
2. Keep changes focused and avoid committing local configuration, credentials, caches, or real screenshots.
3. Run:

```bash
sh scripts/test.sh
sh scripts/build.sh
sh scripts/package-dmg.sh
```

4. Open a pull request describing the behavior change and how it was verified.

UI changes should update deterministic `1280×720` snapshots when needed. Regenerate public screenshots only with `sh scripts/export-readme-screenshots.sh`.
