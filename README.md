# Adaptive Dictionary for TypeWhisper

A private, local post-processing plugin that learns how you correct dictated text. Casing fixes activate immediately; other replacements activate after the same correction is observed twice. Every rule can be reviewed, disabled, or deleted.

## Privacy

- No API keys, telemetry, HTTP clients, or network requests.
- Correction data stays in TypeWhisper's plugin data directory.
- It never enables or interacts with TypeWhisper's optional contribution uploader.
- Disabling the plugin immediately stops its Accessibility-based edit observer.

## Build and verify

Requirements: TypeWhisper in `/Applications`, Xcode 16+, XcodeGen, and Swift 6.

The build script reads the installed TypeWhisper version and compiles against that exact tagged SDK source. The plugin links to the SDK framework already shipped inside the app.

```sh
swift test
scripts/build.sh
scripts/verify.sh
```

Install and restart TypeWhisper:

```sh
scripts/install.sh
```

The plugin appears under TypeWhisper's post-processors as **Adaptive Dictionary**.

In its settings, learning can be paused, the confirmation threshold can be changed from one to five observations, and every rule can be disabled or deleted.

## Learning loop

1. TypeWhisper inserts dictated text.
2. You correct that inserted text and commit with Return, Tab, or a focus/app change.
3. Adaptive Dictionary extracts small word or phrase replacements and stores them locally.
4. A casing-only rule becomes active immediately. Other rules become active after the configured number of matching observations.
5. Active rules run as a deterministic post-processor on future transcriptions.

This project is licensed under GPL-3.0-only to remain compatible with TypeWhisper.
