# Security Policy

## Supported Versions

Security fixes target the latest GlancePane release.

## Reporting a Vulnerability

Please use GitHub's **Security > Report a vulnerability** flow instead of opening a public issue. Include the affected version, reproduction steps, and impact. Do not include real credentials, private keys, session files, or personal configuration in the report.

## Secret Handling

Never commit QWeather private keys, JWTs, exported personal configuration, caches, or session data. GitHub Secret Scanning, push protection, and Gitleaks run as repository safeguards, but contributors remain responsible for reviewing changes before pushing.
