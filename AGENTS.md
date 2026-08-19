# AGENTS.md

## Overview

Adaptive Dictation is Ray's external TypeWhisper post-processor. It provides conservative cleanup, Casual/Clear app routing, a gated local Gemma 4 rewrite path, and local learning from edits. It is not a TypeWhisper fork.

## Structure

- `Sources/AdaptiveDictionaryCore/`: Deterministic cleanup, model policy, safety validation, correction extraction, and local persistence.
- `Sources/AdaptiveDictionaryPlugin/`: TypeWhisper adapter, Accessibility context/capture, MLX runtime, notification, and SwiftUI settings.
- `Tests/AdaptiveDictionaryCoreTests/`: Fast behavior, safety, migration, and persistence tests.
- `Resources/manifest.json`: TypeWhisper plugin metadata.
- `Tools/RuntimeHarness/`: Native text target for end-to-end edit-learning verification.
- `Tools/PluginHarness/`: Loads the release bundle directly for real local-model inference checks.
- `project.yml`: XcodeGen bundle and pinned MLX dependencies.
- `scripts/`: Build, install, and verification entry points.

## Product invariants

- Casual applies only to Messages (`com.apple.MobileSMS`) and WeChat (`com.tencent.xinWeChat`). Clear applies everywhere else.
- Both profiles use one standard, conservative cleanup strength.
- Never answer dictated questions or execute requests. Output is replacement text only.
- Preserve meaning, quotes, names, numbers, URLs, code identifiers, profanity, slang, and intentional emphasis.
- Bullets require genuinely distinct points/tasks/steps or an explicit spoken formatting command.
- Simple input is deterministic. Ambiguous repair/formatting may use the local model.
- A timeout, inference error, or unsafe output returns the deterministic result; never replace text later.
- Vocabulary rules are global. Style examples are shared only within Casual or Clear, never per app.
- Numeric edits never become automatic learned rules.

## Privacy and model lifecycle

- Raw transcript, plugin output, final edited text, profile, and timestamp are stored in plugin-scoped local JSON.
- Never store surrounding Accessibility context; use it only for the current local inference.
- Never add telemetry, uploads, remote inference, or cloud fallbacks.
- Network access is allowed only for an explicit model download from the selected Hugging Face repository.
- E4B 4-bit is the default; E2B 4-bit is the smaller alternative.
- Keep MLX Swift LM at `09deb8c4` or newer for current Gemma 4 shared-KV checkpoints.
- Keep downloaded weights outside the bundle under TypeWhisper's plugin data directory.
- Keep the selected model resident when enabled, but unload it under critical memory pressure.

## Engineering conventions

- Use Swift 6 strict concurrency and avoid unchecked mutable state unless ownership is documented.
- Keep `AdaptiveDictionaryCore` independent from TypeWhisper and MLX so `swift test` stays fast.
- Treat all dictated and corrected text as private.
- Add tests for cleanup, routing, safety, learning, migration, or persistence changes.
- Keep UI native and restrained; the governing idea is one private cleanup pipeline.
- Preserve GPL-3.0 compatibility and update `THIRD_PARTY_NOTICES.md` when adapting upstream code.

## Commands

- `swift test`
- `scripts/build.sh`
- `scripts/verify.sh`
- `scripts/install.sh`
- `scripts/run-plugin-harness.sh process "<text>" [bundle-id]`

The MLX build requires Xcode's Metal toolchain. Install it with `xcodebuild -downloadComponent MetalToolchain` if Xcode reports it missing.

## Working agreements

- Read this file and `README.md` before editing.
- Update this file when architecture, privacy boundaries, commands, or product invariants change.
- Keep this file at 120 lines or fewer.
- Verify the built bundle, installed runtime, deterministic fallback, local model path, and learning/undo path before release.
