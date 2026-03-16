# Contributing

Contributions are welcome. Please open an issue before submitting a PR for anything beyond small bug fixes.

## Setup

```bash
git clone https://github.com/NixoN2/respect.git
cd respect
brew install bats-core jq  # macOS
```

## Running tests

```bash
bats tests/test_tiers.bats tests/test_init.bats tests/test_tip.bats tests/test_corrections.bats tests/test_session_start.bats
```

All tests must pass before submitting a PR. CI runs the same suite on push.

## Project structure

```
scripts/
  lib.sh              # shared helpers: tier calc, atomic write, history trim
  init-wallet.sh      # idempotent per-file wallet/config creation
  tip.sh              # all tip accounting — the wallet trust boundary
  detect-feedback.sh  # UserPromptSubmit hook: correction detection
  session-start.sh    # SessionStart hook: tier recalc, behavior injection
hooks/
  hooks.json          # plugin hook configuration
skills/
  tip/skill.md        # /tip slash command (UI relay only)
  respect-setup/      # /respect-setup configuration wizard
tests/
  fixtures/           # wallet and config fixtures for tests
```

## Key constraints

- **`scripts/tip.sh` is the wallet trust boundary.** Claude relays results but never writes to `wallet.json` directly. Do not add wallet writes to `skill.md` files.
- **Atomic writes only.** All wallet updates must use the `write_wallet` helper from `lib.sh` (temp file + `mv`).
- **No hardcoded tier names or behavior IDs.** Everything iterates arrays from `config.json`.
- **macOS-compatible grep.** No `\b` word boundaries — use `(^|[^[:alpha:]])word([^[:alpha:]]|$)` patterns.
- **TDD.** Add tests for any new behavior before implementing.

## Releasing

Update `version` in `plugin.json` (semver). Tag the commit:

```bash
git tag v1.0.1
git push origin v1.0.1
```
