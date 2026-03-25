---
title: Billing & Licensing Architecture — FluentCart + Control-Plane Pattern
type: foundation-guide
status: active
authority: primary
intent-scope: licensing,billing,control-plane,plugin-development
last-reviewed: 2026-03-20
---

# Billing & Licensing Architecture — FluentCart + Control-Plane Pattern

## Overview

This document captures the proven 2-plugin billing and licensing architecture used in WebMasterOS. It is the foundation template for any future WordPress product that needs SaaS-style per-site licensing with plan-based feature allowances.

The system has two independent WordPress plugins:

| Plugin | Runs on | Purpose |
|--------|---------|---------|
| **Control-plane plugin** | Your billing WP site (private) | Exposes REST API; validates license keys against FluentCart; issues and stores site activations; returns plan limits |
| **Customer plugin** | Each customer's WP site | Stores activation credentials; periodically syncs entitlement contract from control-plane; gates features behind plan limits |

The billing site itself is a standard WordPress install running **FluentCart Pro** for product/license management.

---

## Auth Flow

```
Customer Site                          Billing Site (Control Plane)
─────────────────────────────────────────────────────────────────
1. User enters license key in WP Admin Settings
   │
2. POST /activations
   { license_key, site_url, site_fingerprint, plugin_version }
   │──────────────────────────────────────────────────────────▶
   │                   FluentCartNativeResolver looks up key
   │                   in FluentCart's DB tables
   │                   PlanRegistry maps product_id → plan slug
   │                   activation_id + site_token generated
   │◀─────────────────────────────────────────────────────────
   { activation_id, site_token, plan, product_id }
   │
3. Customer site stores activation_id, site_token in WP options
   │
4. POST /entitlements/resolve (periodic: hourly, admin page load)
   Header: X-WMOS-Site-Token: <site_token>
   { activation_id, site_fingerprint, plugin_version, reason }
   │──────────────────────────────────────────────────────────▶
   │                   Lookup activation by activation_id
   │                   Verify site_token with hash_equals()
   │                   Verify site_fingerprint matches stored
   │                   BillingAllowanceRepository reads
   │                     wmos_allowances_v1 product meta
   │                   Build entitlement contract
   │◀─────────────────────────────────────────────────────────
   { plan, limits: {...}, activation_policy: {...} }
   │
5. Customer site caches entitlement contract in WP options
   Features are gated using cached contract
```

### Credential summary

| Credential | Who generates | Stored where | Used for |
|------------|---------------|--------------|----------|
| `license_key` | FluentCart (billing site) | Customer WP options | Initial activation only |
| `activation_id` | Control-plane endpoint | Customer WP options + CP DB | Identifying the activation |
| `site_token` | Control-plane endpoint | Customer WP options + CP DB | Authenticating entitlement resolves |
| `site_fingerprint` | Customer site (SHA-256 of URLs) | CP activation record | Binding activation to specific site |

**No HMAC shared secret.** The license key is the sole activation credential. After activation, `site_token` is the per-activation bearer credential. There is no server-to-server shared secret that needs out-of-band distribution.

---

## FluentCart Billing Site Setup

### 1. Install FluentCart Pro

Install FluentCart Pro on your billing WordPress site. Enable the **Licensing** module.

### 2. Create Products

Create one product per plan tier. Recommended pattern:

| Plan slug | Product title | Notes |
|-----------|---------------|-------|
| `freemium` | Freemium | Free tier — no paid license required |
| `solo` | Solo | Entry paid tier, 1 site activation |
| `maestro` | Maestro | Mid tier, 3 site activations |
| `agency` | Agency | Top tier, 10+ site activations |

Each product needs at least one **variation** (FluentCart's term for pricing tier within a product). Note the `product_id` (numeric, from FluentCart's DB) and `variation_id` for each.

### 3. Configure License Settings per Product

In FluentCart → Product → License Settings:
- Enable licensing for the product
- Set activation limit (max sites per license key)
- Enable license key auto-generation on purchase

### 4. Set Product Metadata (`wmos_allowances_v1`)

This is the **most important step**. The control-plane reads feature allowances from a custom metadata key stored on each FluentCart product.

Use the `check-data-source-baseline.sh` script (or set directly in WP options/post meta) to write:

```
Meta key:   wmos_allowances_v1
Object:     FluentCart product post (the post_id of the product)
```

**Allowances payload format (JSON, stored serialized):**

```json
{
  "ai_credits_monthly": 500,
  "ai_chat_messages_monthly": 200,
  "max_site_activations": 1,
  "feature_flags": {
    "ai_chat": true,
    "advanced_reports": false
  }
}
```

Adjust keys to match your product's actual feature set. The control-plane's `BillingAllowanceRepository` reads this meta and returns it as the `limits` object in the entitlement contract.

**Variation-specific overrides** can be nested:

```json
{
  "ai_credits_monthly": 100,
  "variation_overrides": {
    "2": { "ai_credits_monthly": 500, "max_site_activations": 1 },
    "3": { "ai_credits_monthly": 2000, "max_site_activations": 3 }
  }
}
```

### 5. Configure PlanRegistry in Control-Plane Plugin

Open `includes/Modules/Licensing/PlanRegistry.php` and list your product references:

```php
$rows = [
    [ 'plan' => 'solo',    'product_id' => 2569, 'variation_id' => 2 ],
    [ 'plan' => 'maestro', 'product_id' => 2571, 'variation_id' => 3 ],
    [ 'plan' => 'agency',  'product_id' => 2573, 'variation_id' => 4 ],
];
```

`product_id` and `variation_id` here are **FluentCart's internal IDs** (not WP post IDs). Use the `debug_probe()` method on `FluentCartNativeResolver` to discover them when a license key is available.

---

## REST API Contract

**Base namespace:** `{cp-plugin-slug}/v1`
**Base URL:** `https://{billing-site}/wp-json/{cp-plugin-slug}/v1/`

All requests use `Content-Type: application/json`. After activation, all requests include:
```
X-WMOS-Site-Token: <site_token>
```

### POST `/activations`

Creates a new site activation for a license key.

**Request body:**
```json
{
  "license_key": "XXXX-XXXX-XXXX-XXXX",
  "site_url": "https://customer.example.com/",
  "site_fingerprint": "A3B9F2C1D4E8A1B2",
  "plugin_version": "0.1.15"
}
```

**Success (200):**
```json
{
  "success": true,
  "data": {
    "status": "active",
    "activation_id": "act_<20 chars>",
    "site_token": "st_<32 chars>",
    "plan": "solo",
    "product_id": 2569,
    "plugin_version": "0.1.15"
  },
  "error": null
}
```

**Failure (403):**
```json
{
  "success": false,
  "data": { "status": "invalid_license" },
  "error": "Unable to find this license key...",
  "code": "no_native_license_match"
}
```

### POST `/entitlements/resolve`

Resolves the current entitlement contract for an activation. Called periodically (hourly, on admin load, on feature use).

**Headers:** `X-WMOS-Site-Token: <site_token>`

**Request body:**
```json
{
  "activation_id": "act_...",
  "site_fingerprint": "A3B9F2C1D4E8A1B2",
  "plugin_version": "0.1.15",
  "reason": "sync"
}
```

**Success (200):**
```json
{
  "success": true,
  "data": {
    "status": "active",
    "plan": "solo",
    "limits": {
      "ai_credits_monthly": 500,
      "max_site_activations": 1
    },
    "activation_policy": {
      "max_activations": 1,
      "used_activations": 1,
      "remaining_activations": 0
    },
    "contract_signature": "<hash>"
  },
  "error": null
}
```

**Failure — activation not found (404)** / **token invalid (403)** / **allowances not configured (424)**

### GET `/health`

Simple liveness check, no auth required.

**Response (200):** `{ "status": "ok", "version": "0.1.40" }`

### POST `/debug/trace` _(dev/staging only)_

Only registered when `WMOS_LICENSE_DEV_UI` constant is `true`. Returns ops telemetry + activation debug info. Requires `X-WMOS-Site-Token` header.

---

## Site Fingerprint

The site fingerprint is a 16-char uppercase hex string derived from:

```php
SHA256( network_home_url('/') | home_url('/') | site_url('/') | blog_id )
// Take first 16 hex chars, uppercase
```

It is computed fresh on every API call and compared against the value stored at activation time. A mismatch returns 403. This prevents activations from being replayed or transferred across sites.

---

## Activation Storage (Control-Plane)

Activations are stored in a single WP option `{cp_option_prefix}_activations` as an associative array keyed by `activation_id`. Each record contains:

```php
[
  'activation_id'        => 'act_...',
  'site_token'           => 'st_...',
  'license_key'          => 'XXXX-...',           // full key (keep safe)
  'license_key_ref'      => 'XXXX...XXXX',         // first4..last4 for logging
  'license_status'       => 'active',
  'plan'                 => 'solo',
  'product_id'           => 2569,
  'variation_id'         => 2,
  'max_site_activations' => 1,
  'site_url'             => 'https://...',
  'site_fingerprint'     => 'A3B9...',
  'created_at'           => '2026-03-20T...',
  'updated_at'           => '2026-03-20T...',
]
```

> **Phase 1 note:** This option-based storage works well for up to ~hundreds of activations. For scale, migrate to a custom DB table (activation_id as primary key, indexed on license_key).

---

## Entitlement State (Customer Plugin)

The customer plugin stores activation credentials and the cached entitlement contract in WP options:

| Option key (template) | Content |
|----------------------|---------|
| `{customer_prefix}_license_key` | Raw license key (write once, user-entered) |
| `{customer_prefix}_cp_activation_id` | `act_...` returned by `/activations` |
| `{customer_prefix}_cp_site_token` | `st_...` returned by `/activations` |
| `{customer_prefix}_cp_activation_license_ref` | `XXXX...XXXX` — used to detect key change |
| `{customer_prefix}_license_entitlement` | Full cached contract array from last resolve |
| `{customer_prefix}_license_last_sync` | ISO timestamp of last successful resolve |
| `{customer_prefix}_license_last_error` | Human-readable error from last failed sync |

---

## Dev/Debug Mode

Set `WMOS_LICENSE_DEV_UI = true` (or your equivalent constant) in `wp-config.php` or `docker-compose.yml` to:

- Enable the `/debug/trace` endpoint (registered in RestRouter only when constant is true)  
- Enable `FluentCartNativeResolver::debug_probe()` output in activation error responses
- Enable debug event logging in `LicenseApiClient` (stored in WP options, viewable in admin)

Never enable this on production billing sites.

---

## Security Decisions

| Decision | Rationale |
|----------|-----------|
| No HMAC shared secret | Eliminates a credential that needs out-of-band distribution; reduces attack surface; the site_token already provides per-activation bearer auth |
| Billing URL hardcoded in customer plugin | Prevents customers from redirecting license checks to a rogue server; no admin-exposed override |
| `hash_equals()` for site_token comparison | Constant-time comparison prevents timing attacks |
| Activation record stores `license_key_ref` only in logs | Full key never appears in error logs or API responses |
| `site_fingerprint` bound at activation | Prevents activation tokens from being copied between sites |
| `permission_callback` returns true on endpoints | Intentional — auth is done inside `handle()` to return JSON errors instead of WP's generic 401. The callback returns `true` (open) while the handler performs all credential validation and returns structured JSON error responses. |

---

## New Product Checklist

When creating a new SaaS WP plugin with this licensing architecture:

**Billing site (do once per product family):**
- [ ] Install FluentCart Pro, enable Licensing module
- [ ] Create products (one per plan tier), note `product_id` and `variation_id`
- [ ] Configure license settings per product (activation limit, auto-generate key)
- [ ] Set `wmos_allowances_v1` metadata on each product with the feature limits JSON
- [ ] Install the control-plane plugin (from this template), configure `PlanRegistry`

**Control-plane plugin (from template):**
- [ ] Copy `foundation/wp/templates/licensing/control-plane/` as starting point
- [ ] Replace all `{{TOKEN}}` placeholders (see template headers)
- [ ] Update `PlanRegistry` with your product_id/variation_id/plan mappings
- [ ] Update `BillingAllowanceRepository` if your allowance keys differ from defaults
- [ ] Test activation + entitlement resolve against staging billing site
- [ ] Add `WMOS_LICENSE_DEV_UI` to prod `wp-config.php` as `false`

**Customer plugin (from template):**
- [ ] Copy `foundation/wp/templates/licensing/customer-plugin/` as starting point
- [ ] Replace all `{{TOKEN}}` placeholders
- [ ] Set `BILLING_CP_URL` to your billing site's REST base URL (hardcoded constant)
- [ ] Wire `LicenseApiClient::sync()` to your cron hook (e.g. `wp_schedule_event`)
- [ ] Wire sync to admin settings page save
- [ ] Add Settings page UI: license key input + status display
- [ ] Gate features behind `LicenseStateStore::get_cached_entitlement()['plan_slug']` checks

---

## File Reference (WebMasterOS implementation)

| Template | Implemented as |
|----------|----------------|
| `control-plane/cp-plugin-main.php.template` | `private-plugins/wmos-control-plane/wmos-control-plane.php` |
| `control-plane/.../RestRouter.php.template` | `...includes/API/RestRouter.php` |
| `control-plane/.../ActivationCreateEndpoint.php.template` | `...includes/API/Endpoints/ActivationCreateEndpoint.php` |
| `control-plane/.../EntitlementResolveEndpoint.php.template` | `...includes/API/Endpoints/EntitlementResolveEndpoint.php` |
| `control-plane/.../RequestVerifier.php.template` | `...includes/Auth/RequestVerifier.php` |
| `control-plane/.../ActivationRepository.php.template` | `...includes/Modules/Licensing/ActivationRepository.php` |
| `control-plane/.../BillingAllowanceRepository.php.template` | `...includes/Modules/Licensing/BillingAllowanceRepository.php` |
| `control-plane/.../PlanRegistry.php.template` | `...includes/Modules/Licensing/PlanRegistry.php` |
| `control-plane/.../FluentCartNativeResolver.php.template` | `...includes/Modules/Licensing/FluentCartNativeResolver.php` |
| `customer-plugin/.../LicenseStateStore.php.template` | `webmasteros/includes/Licensing/LicenseStateStore.php` |
| `customer-plugin/.../LicenseApiClient.php.template` | `webmasteros/includes/Licensing/LicenseApiClient.php` |
| `customer-plugin/.../SiteFingerprint.php.template` | `webmasteros/includes/Licensing/SiteFingerprint.php` |
