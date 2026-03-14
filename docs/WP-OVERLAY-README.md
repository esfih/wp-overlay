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

## Local Migration Rule

During staging inside this repository:

- add reusable WordPress assets here first
- keep current root/runtime files authoritative until adapters are in place
- do not move product plugin code into this folder