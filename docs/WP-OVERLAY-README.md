---
title: WordPress Overlay Staging
type: foundation-guide
status: active
authority: primary
intent-scope: workspace-setup,implementation,release,maintenance
phase: extraction
last-reviewed: 2026-03-14
---

# WordPress Overlay Staging

## Purpose

This folder defines the reusable WordPress-specific overlay that should later live in the separate `wp-overlay` repository.

It is the upstream candidate for:

- local Docker WordPress development scaffolding
- plugin ZIP packaging helpers
- WordPress-specific validation scripts
- shared-hosting runtime assumptions
- example plugin skeletons and release manifest templates

## Must Belong Here

- reusable WordPress runtime assets
- reusable plugin packaging and verification logic
- WordPress plugin templates and sample manifests
- WordPress-specific setup addenda that can serve many app repos

## Must Not Belong Here

- one product's plugin code
- one product's feature specs or commercial decisions
- private billing-site logic
- generated build artifacts

## Reusable Local Sandbox Rule

For WordPress plugin development, the overlay should prefer pinned core images over floating tags.

Use this pattern by default:

1. keep the main local sandbox pinned to the current supported baseline
2. add a second isolated sandbox for the next WordPress release or beta lane
3. give each sandbox its own database, volumes, and localhost ports
4. mount the same plugin source into both sandboxes so one code change can be tested against both

Why:

- floating tags hide baseline drift
- plugin regressions are easier to isolate when each core line has its own state
- WordPress beta or prerelease testing should not contaminate the stable dev lane

## Shared Docker Pattern

The staged overlay Dockerfile accepts a `WORDPRESS_BASE_IMAGE` build arg so app repos can pin exact WordPress core tags while reusing the same dev image customizations.

Recommended default shape:

- baseline lane: exact stable tag such as `wordpress:6.9.4-php8.2-apache`
- comparison lane: exact prerelease tag such as `wordpress:beta-7.0-beta5-php8.2-apache`

The staged Compose template includes:

- one primary WordPress lane using `WP_IMAGE`
- one optional secondary lane behind the `dual-version` profile using `WP_NEXT_IMAGE`
- separate `WP_PORT` and `WP_NEXT_PORT`
- separate DB names, users, prefixes, and volumes for each lane

## Reuse Notes For App Repos

When an app repo needs only one local WordPress instance, it can ignore the optional `dual-version` profile entirely.

When an app repo needs version-comparison work, it should:

1. pin the baseline lane first
2. add the second lane on a different localhost port
3. keep validation scripts aware of which lane is required versus optional
4. document the chosen stable tag and comparison tag in the app-local runtime files

## Local Migration Rule

During staging inside this repository:

- add reusable WordPress assets here first
- keep current root/runtime files authoritative until adapters are in place
- do not move product plugin code into this folder