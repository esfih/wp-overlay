---
title: Control-Plane Plugin — Reuse Guide
type: foundation-guide
status: active
authority: primary
intent-scope: workspace-setup,implementation
phase: reuse
last-reviewed: 2026-03-25
related-files:
  - ./BILLING-LICENSING-ARCHITECTURE.md
  - ../templates/licensing/control-plane/
  - ../templates/licensing/customer-plugin/
  - ./WP-OVERLAY-README.md
---

# Control-Plane Plugin — Reuse Guide

## Overview

Every product in this stack uses the **two-plugin billing pattern**:

| Plugin | Site | Purpose |
|---|---|---|
| **Control-plane plugin** | Billing site (your FluentCart site) | License activations, entitlement resolution, plan allowances, operator dashboard |
| **App/Customer plugin** | Customer's WordPress site | License state, API client, feature gating based on allowances |

The control-plane plugin is **reusable across products**. Only the following change per product:

- The FluentCart product ID(s)
- The plan slugs and their allowance values
- The plugin namespace and text domain

Everything else — auth flow, activation REST endpoint, entitlement resolution, token management —
is identical and reuse-ready.

---

## How to Bootstrap a New Control-Plane Plugin

### Step 1 — Copy the templates

```bash
cp -r foundation/wp/templates/licensing/control-plane/ cp-plugin/
```

### Step 2 — Rename class files

Replace the `.template` suffix on each file:
```bash
for f in $(find cp-plugin -name "*.template"); do mv "$f" "${f%.template}"; done
```

### Step 3 — Update namespaces

Replace `YourProduct` in all PHP files with your product namespace (e.g. `MySaas`):
```bash
find cp-plugin -name "*.php" -exec sed -i 's/YourProduct/MySaas/g' {} +
```

### Step 4 — Configure the plan registry

Edit `cp-plugin/includes/Auth/PlanRegistry.php`:
```php
private const PRODUCT_PLANS = [
    12345 => 'starter',   // FluentCart product_id => plan slug
    12346 => 'pro',
    12347 => 'agency',
];
```

### Step 5 — Configure allowances

Edit `cp-plugin/includes/Modules/Licensing/BillingAllowanceRepository.php`:
```php
private const PLAN_ALLOWANCES = [
    'starter' => [
        'sites'    => 1,
        'feature_x' => 50,
    ],
    'pro' => [
        'sites'    => 5,
        'feature_x' => 500,
    ],
];
```

### Step 6 — Update the plugin header

Edit `cp-plugin/my-saas-cp.php`:
```php
/**
 * Plugin Name: My SaaS — Control Plane
 * Version:     0.1.0
 * Requires at least: 6.5
 * Requires PHP: 8.1
 */
```

---

## Reference Implementation

The production reference implementation is `private-plugins/wmos-control-plane` in the
WebMasterOS app repository:

- `https://github.com/esfih/WebMasterOS`

That plugin is the source of truth for the current auth flow, REST contract, admin dashboard,
and operator policy decisions. When you adapt the templates for a new product, model your
implementation on that reference.

---

## Auth Flow (same for all products)

```
Customer site → POST /wp-json/cp/v1/activations
  body: { license_key, site_url, site_token_request }

Control-plane (billing site):
  1. FluentCartNativeResolver: find order in FluentCart DB by license_key
  2. PlanRegistry: map product_id → plan_slug
  3. BillingAllowanceRepository: read plan allowances
  4. Generate site_token (signed, expires 30 days)
  5. Return: { site_token, plan_slug, allowances }

Customer site:
  - Store site_token + allowances in wp_options
  - LicenseStateStore: gate features based on allowance values
  - Refresh token before expiry
```

**Security model:** License key → activation → `site_token`. No HMAC shared secret.
Control-plane URL is hardcoded in the customer plugin. See
`foundation/wp/docs/licensing/BILLING-LICENSING-ARCHITECTURE.md` for full rationale.

---

## What Changes Per Product

| Config Point | Location | What to change |
|---|---|---|
| FluentCart product IDs | `PlanRegistry.php` | Your product's FluentCart order product IDs |
| Plan slugs | `PlanRegistry.php` | Your plan tier names |
| Allowance keys and values | `BillingAllowanceRepository.php` | Feature quotas per plan |
| Plugin namespace | All PHP files | Product-specific PHP namespace |
| Plugin slug | Plugin header | WordPress plugin slug |
| Control-plane URL | Customer plugin `LicenseApiClient.php` | Your billing site domain |

## What Never Changes

- REST endpoint contract (`POST /activations`, `POST /entitlements/resolve`)
- Token generation and verification logic
- Site fingerprint algorithm
- FluentCart order lookup pattern
- Local state refresh cycle

---

## Keeping in Sync

As the reference implementation (`wmos-control-plane`) evolves, cherry-pick security fixes and
auth flow improvements back into your product's control-plane plugin by reviewing diffs against
`foundation/wp/templates/licensing/control-plane/`.

When significant improvements land in the reference, update the templates here in `wp-overlay`
so all downstream products can benefit.
