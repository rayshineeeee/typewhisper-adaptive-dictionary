# Adaptive Dictation rollout

- Verified on 2026-08-19 with TypeWhisper 1.5.1 (build 928).
- Installed bundle ID: `com.raysun.typewhisper.adaptive-dictionary`.
- Installed display name: Adaptive Dictation 1.1.0.
- Selected model: `mlx-community/gemma-4-e4b-it-4bit` in plugin-scoped local storage.
- MLX Swift LM is pinned to `09deb8c4` for the current shared-KV checkpoint format.
- Enabled state: plugin on, semantic cleanup on, recording-triggered loading, learning on, two confirmations.
- Verified lifecycle: 1.28-1.80 s cached recording-trigger load, 1.60 s immediate load-plus-rewrite, then unload after idle.
- Verified TypeWhisper idle physical footprint after unload: 31 MB; loaded model footprint was about 4.5 GB.
- Disabled TypeWhisper's overlapping Filler Words post-processor; Parakeet vocabulary boosting remains on.
- TypeWhisper's local HTTP API was restored to off after verification.
