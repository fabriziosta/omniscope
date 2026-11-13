# Security Policy

## Supported versions

Security fixes are applied on the default branch (`main`) of this repository.
There are no long-term support releases yet; please upgrade to the latest
commit or release when a fix is published.

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Report privately by emailing **fabriziosta92@gmail.com** with:

- A short description of the issue and its impact
- Steps to reproduce (or a proof of concept if you have one)
- Affected platform(s), if known (Linux, Windows, Android, iOS, macOS, Web)
- Whether the issue involves secrets, local config (`omniscope.json`), or
  third-party APIs

You should receive an acknowledgement within a few days. We will coordinate a
fix and credit (if you want it) before any public disclosure.

## Scope notes for this project

Omniscope is an educational, on-device app (no cloud accounts in v0). Reports
that are especially useful include:

- Accidental logging or leakage of API keys / exchange credentials
- Path traversal or unsafe handling of the custom config file path (desktop)
- XSS or similar issues in the Web build
- Dependency vulnerabilities that are exploitable in this app’s context

Out of scope (unless they cause a concrete vulnerability here):

- Issues solely in third-party market-data or LLM provider services
- Social-engineering users into pasting secrets into chat or Settings
- Theoretical risks without a realistic exploit path

## Secrets hygiene

- Never commit `.env`, API keys, or credential JSON
- Prefer Settings / local config for keys; treat `omniscope.json` as sensitive
- See [CONTRIBUTING.md](CONTRIBUTING.md) and the pre-commit hooks (gitleaks)
