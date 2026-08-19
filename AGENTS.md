# AGENTS.md

## Overview

Adaptive Dictionary is a local-only TypeWhisper post-processor for Ray. It learns repeated corrections made after dictation, then applies confirmed corrections before future text is inserted.

## Folder Structure

- `Sources/AdaptiveDictionaryCore/`: Diffing, confidence, persistence, and deterministic replacement logic.
- `Sources/AdaptiveDictionaryPlugin/`: TypeWhisper SDK adapter, privacy guard, and SwiftUI settings.
- `Tests/AdaptiveDictionaryCoreTests/`: Behavior and persistence tests for the engine.
- `Resources/manifest.json`: TypeWhisper plugin metadata.
- `Tools/RuntimeHarness/`: Deterministic native text target used only for runtime verification.
- `project.yml`: XcodeGen definition for the macOS bundle.
- `scripts/`: Repeatable build, install, and verification commands.

## Core Behaviors & Patterns

- Corrections are local JSON under TypeWhisper's plugin-scoped data directory.
- Casing-only fixes activate immediately; other corrections need two observations by default.
- Rules are global, while observed target-app bundle IDs are retained as review context.
- Replacements are boundary-aware, longest-match-first, and non-cascading.
- The plugin contains no networking code and never enables TypeWhisper's contribution capture.
- Post-insertion edits are observed through the host process's existing Accessibility permission.

## Conventions

- Use Swift 6 concurrency checking and avoid unchecked shared mutable state.
- Keep the core module independent from TypeWhisper so `swift test` remains fast.
- Treat raw dictated and corrected text as private user data.
- Add tests for every change to extraction, activation, matching, or persistence behavior.
- Keep the settings UI native, restrained, and operational rather than decorative.

## Working Agreements

- Read this file and `README.md` before making changes.
- Prefer small, verifiable edits over broad rewrites.
- Update this file when project structure, commands, or durable constraints change.
- Keep this file at 120 lines or fewer.
- Verify with `swift test`, `scripts/build.sh`, and `scripts/verify.sh`.
- Never add telemetry, uploads, remote inference, or automatic network access.
