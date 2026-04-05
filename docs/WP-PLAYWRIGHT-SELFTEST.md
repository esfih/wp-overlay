---
title: Playwright IDE AI Self-Test Harness
type: foundation-guide
status: active
authority: primary
intent-scope: testing,debugging,qa,ide-ai-autonomy
phase: active
last-reviewed: 2026-04-05
ide-context-token-estimate: 2200
token-estimate-method: approx-chars-div-4
related-files:
  - WP-LOCAL-OPS.md
  - WP-REMOTE-OPS.md
  - ../scripts/playwright-selftest.sh
  - ../scripts/install-playwright-system.sh
---

# Playwright IDE AI Self-Test Harness

## Purpose

Give the IDE AI agent full autonomy to:

1. **Self-test** — run browser-driven checks against the local WordPress runtime without user intervention.
2. **Self-debug** — reproduce a UI/JS regression, collect trace evidence, and identify root cause.
3. **Verify changes** — after implementing a fix, confirm the intended UI behaviour is present before reporting completion.

This file is the **setup and operating reference**. Read `WP-LOCAL-OPS.md` first for the Docker runtime prerequisite.

---

## When to Use Playwright (IDE AI Decision Rule)

Use the Playwright self-test harness **before** asking the user for manual browser evidence whenever:

- Implementing or modifying a frontend feature (JS, CSS, template).
- Debugging a regression report (UI element missing, wrong class, broken navigation).
- Verifying a plugin or theme update did not break visible behaviour.
- Confirming an auto-update or deployment succeeded and the site is healthy.

**Never wait for user-provided screenshots or console logs as a first step.**  
Run catalog commands first; ask for manual evidence only if local reproduction fails.

---

## Architecture Overview

```
scripts/
  playwright-selftest.sh          ← single entry point for all Playwright actions
  install-playwright-system.sh    ← system-level Chromium + dep installer (one-time)

tools/playwright/
  playwright.config.ts            ← Playwright config (baseURL, reporters, timeouts)
  package.json / package-lock.json
  node_modules/                   ← local Playwright install (gitignored)
  tests/
    site-smoke.spec.ts            ← @smoke tagged suite  (HTTP/JS health)
    clickable-interactions.spec.ts ← @interactions tagged suite (scenario-driven)
    player-regression.spec.ts     ← feature regression tests
    fixtures/
      interactions.template.json  ← generic scenario template to copy for new flows
      interactions.*.json         ← app-specific scenario packs
  playwright-report/              ← HTML report artifact (gitignored)
  test-results/                   ← screenshots, traces, videos on failure (gitignored)
```

Key design decisions:

- **Repo-local Playwright install** — `tools/playwright/node_modules/` ensures version pinning and avoids global collisions.
- **Local-node-first, Docker fallback** — `playwright-selftest.sh` uses the system Linux Node if available; falls back to Official Playwright Docker image when Node is absent from the Linux PATH (common on WSL2 when Windows npm is on the PATH instead of Linux npm).
- **Single-process, `workers: 1`** — avoids race conditions against a shared local WordPress.
- **Artifacts retained on failure** — `trace: 'retain-on-failure'`, `screenshot: 'only-on-failure'`, `video: 'retain-on-failure'`.

---

## Initial Setup (One-Time Per Machine)

### Prerequisites

- Docker containers running (see `WP-LOCAL-OPS.md`).
- Linux Node.js and npm installed (`node` resolves to a **non-Windows-mounted** binary on WSL2).

```bash
# Verify Linux Node is on the PATH (must NOT be under /mnt/c):
which node && node --version
```

### Step 1 — Install system Chromium dependencies

```bash
./scripts/run-catalog-command.sh qa.playwright.browsers.install
```

This runs `install-playwright-system.sh` which:
1. Verifies Linux Node/npm are available.
2. Runs `npm install` inside `tools/playwright/` if `node_modules` is absent.
3. Installs all Chromium Linux system dependencies via `playwright install-deps chromium`.
4. Installs the Chromium browser binary to `/root/.cache/ms-playwright/` (or user home on non-root).

Expected output ends with `DONE`.

> This script is the **only approved path** for interactive package-manager operations in the IDE integrated terminal — it is an explicit exception to the generic package-manager restriction.

### Step 2 — Install the repo-local Playwright harness

```bash
./scripts/run-catalog-command.sh qa.playwright.install
```

Installs/refreshes `tools/playwright/node_modules` and runs `playwright install chromium` to ensure the pinned browser version matches `package.json`.

Success: `tools/playwright/node_modules/playwright/cli.js` exists.

---

## Standard Self-Test Sequence (IDE AI Canonical Flow)

Run these steps **in order** whenever validating a change:

```bash
# 1. Check local WordPress runtime is healthy
./scripts/run-catalog-command.sh wp.health.check

# 2. Ensure Playwright harness is ready
./scripts/run-catalog-command.sh qa.playwright.install

# 3. Smoke test — fast HTTP/JS health check
./scripts/run-catalog-command.sh qa.playwright.test.smoke

# 4. Interaction test — UI behaviour contract for the changed feature
./scripts/run-catalog-command.sh qa.playwright.test.interactions

# 5. (If failure) Debug mode with trace
./scripts/run-catalog-command.sh qa.playwright.test.debug

# 6. (If failure) Collect full evidence bundle
./scripts/run-catalog-command.sh debug.snapshot.collect 200
./scripts/run-catalog-command.sh wp.debug.log.tail 200
```

---

## Catalog Command Reference

| ID | Command | Purpose |
|---|---|---|
| `qa.playwright.browsers.install` | `./scripts/install-playwright-system.sh` | One-time system + browser install |
| `qa.playwright.install` | `./scripts/playwright-selftest.sh install` | Install/refresh repo-local harness |
| `qa.playwright.test.smoke` | `./scripts/playwright-selftest.sh smoke` | Fast smoke suite (`@smoke`) |
| `qa.playwright.test.interactions` | `./scripts/playwright-selftest.sh interactions [scenario]` | Scenario-driven UI interaction tests (`@interactions`) |
| `qa.playwright.test.debug` | `./scripts/playwright-selftest.sh debug` | Full suite with trace on, workers=1 |
| `qa.playwright.test.headed` | `./scripts/playwright-selftest.sh headed` | Headed mode for visual timing inspection |
| `qa.playwright.report` | `./scripts/playwright-selftest.sh report` | Open HTML report for last run |

Exit code is the canonical pass/fail signal. Non-zero = failure regardless of warning text in stdout.

---

## Smoke Test Suite (`@smoke`)

File: `tools/playwright/tests/site-smoke.spec.ts`

The smoke suite is **tagged `@smoke`** and must run in under 60 seconds. It should assert:

- WordPress home page returns HTTP 200.
- No fatal JS errors on load (console error listener).
- Critical plugin/theme assets are loaded (check link/script tags or page title).

This is intentionally minimal — it gates the interaction suite and confirms the runtime is up.

---

## Interaction Test Suite (`@interactions`)

File: `tools/playwright/tests/clickable-interactions.spec.ts`

Driven by a JSON scenario file. The default scenario file can be set in the project's `playwright.config.ts` or overridden at runtime:

```bash
./scripts/playwright-selftest.sh interactions tests/fixtures/interactions.<feature>.json
```

### Scenario File Format

Base template: `tools/playwright/tests/fixtures/interactions.template.json`

```json
{
  "name": "Feature flow name",
  "pages": [
    {
      "name": "Page description",
      "url": "/relative-path",
      "steps": [
        { "action": "assertVisible", "target": [".primary", "#fallback"] },
        { "action": "click", "target": ".open-button" },
        { "action": "assertHasClass", "target": ".panel", "className": "is-open" },
        { "action": "click", "shadowHosts": ["app-shell"], "shadowTarget": "button.close" },
        { "action": "assertNotHasClass", "target": ".panel", "className": "is-open" },
        { "action": "assertUrlContains", "value": "/expected-segment" },
        { "action": "assertHidden", "target": ".loading-spinner", "optional": true }
      ]
    }
  ]
}
```

### Supported Actions

| Action | Fields | Notes |
|---|---|---|
| `assertVisible` | `target` | Pass array for fallback selectors |
| `assertHidden` | `target` | |
| `click` | `target` | |
| `assertHasClass` | `target`, `className` | |
| `assertNotHasClass` | `target`, `className` | |
| `assertUrlContains` | `value` | Checks `page.url()` |
| `waitFor` | `target` | Waits for selector to appear |

### Selector Options

- `target`: string **or** string array (first matching element wins — use arrays for portability across layouts).
- `within`: scoping selector(s) — restrict lookup to a subtree.
- `optional: true` — step failure is annotated and skipped, not fatal.

### Shadow DOM Support

```json
{ "action": "click", "shadowHosts": ["outer-host", "inner-host"], "shadowTarget": "button.apply" }
```

- `shadowHosts`: ordered array of host selectors from outermost to innermost.
- `shadowTarget`: selector inside the innermost shadow root.
- Works for **open** shadow roots. **Closed** shadow roots require application test hooks.

---

## Base URL Configuration

`playwright.config.ts` reads:

```ts
const baseURL = process.env.ECOMCINE_BASE_URL || 'http://localhost:8180';
```

Override for a different local port or staging URL:

```bash
ECOMCINE_BASE_URL=http://localhost:9000 ./scripts/playwright-selftest.sh smoke
```

---

## Artifact Paths

| Artifact | Location | When Retained |
|---|---|---|
| HTML report | `tools/playwright/playwright-report/` | Always (latest run) |
| Screenshots | `tools/playwright/test-results/` | On failure only |
| Trace files | `tools/playwright/test-results/` | On failure only |
| Video | `tools/playwright/test-results/` | On failure only |
| Debug snapshots | `logs/debug-snapshots/snapshot-<timestamp>.md` | On demand via catalog |

Always include artifact paths in remediation status updates.

---

## WSL2 / Windows Node Pitfall

On WSL2, `which node` may resolve to `/mnt/c/...` — the Windows-hosted Node binary. This fails silently during Playwright browser launch because the Windows binary cannot access Linux socket paths.

`playwright-selftest.sh` guards against this by filtering out `/mnt/c` paths when resolving Node. If it detects the issue it falls back to the Official Playwright Docker image automatically.

To permanently fix: install `nodejs` from apt (`sudo apt-get install -y nodejs`), or use `nvm` within WSL2 to install a Linux-native Node.

---

## Failure Triage Table

| Symptom | Cause | Fix |
|---|---|---|
| `browserType.launch: Executable doesn't exist` | Chromium not installed | Run `qa.playwright.browsers.install` |
| `Error: Cannot find module 'playwright'` | `node_modules` absent | Run `qa.playwright.install` |
| `net::ERR_CONNECTION_REFUSED` | WordPress not running | Run `docker compose up -d` |
| `Timeout: Waiting for selector` | Selector changed or element absent after fix | Update scenario selectors or fix the UI regression |
| `node: command not found` | Linux Node not installed | `sudo apt-get install -y nodejs` |
| `/mnt/c/...` node path | Windows Node resolved in WSL2 PATH | Install Linux Node via apt/nvm |
| Test passes but fix is not visible | Wrong `baseURL` or test against stale cache | Verify `ECOMCINE_BASE_URL` and hard-reload in browser |
