# Adaptive Dictation for TypeWhisper

Adaptive Dictation is a private, external post-processing plugin for TypeWhisper. TypeWhisper continues to own recording, Parakeet transcription, hotkeys, the indicator, insertion, and history. This plugin cleans the transcript before insertion and learns from the edits Ray commits afterward.

## What it does

- Removes obvious fillers such as `um` and `uh` without touching quoted speech.
- Collapses accidental stutters while preserving emphasis such as “very, very” and grammatical repetition such as “had had.”
- Handles ambiguous fillers, self-corrections, spoken formatting commands, and long passages with an optional local Gemma 4 model.
- Uses bullets only for distinct points, problems, tasks, or steps.
- Preserves questions as requests; it never answers or acts as an assistant.
- Applies learned vocabulary corrections before cleanup.
- Learns vocabulary globally and style within one of two profiles.

### Profiles

| Profile | Apps | Output style |
| --- | --- | --- |
| Casual | Messages and WeChat | Ordinary lowercase opening, casual punctuation, no final period |
| Clear | All other and unknown apps | Normal casing and punctuation, conservative structure |

Notes and Notion intentionally use Clear. There is one standard cleanup strength everywhere.

## Processing path

1. Apply confirmed local vocabulary corrections.
2. Run deterministic cleanup and profile styling.
3. Detect whether the text actually needs semantic repair.
4. If needed and ready, ask the resident local model for replacement text.
5. Reject output that answers the speaker, loses protected content, changes numbers/URLs/code identifiers, alters quotes, or rewrites too much.
6. On rejection, error, or timeout, insert the deterministic result. No delayed replacement occurs.

Short model-gated dictation has a two-second deadline. Long passages have a ten-second ceiling. Simple dictation does not pay model latency.

## Local model

- Default: Gemma 4 E4B 4-bit (`mlx-community/gemma-4-e4b-it-4bit`, about 5.2 GB).
- Smaller option: Gemma 4 E2B 4-bit (about 3.6 GB).
- Runtime: MLX on Apple Silicon, adapted from TypeWhisper's GPL-licensed Gemma 4 plugin.
- Lifecycle: optionally resident all day; automatically unloaded under critical memory pressure.

The model downloads only after an explicit setup request. Downloading uses Hugging Face; inference and prompt context stay on the Mac. See [third-party notices](THIRD_PARTY_NOTICES.md).

## Learning and local data

After TypeWhisper inserts text, the plugin watches only that inserted range until Return, Tab, focus change, app change, or a 30-second timeout. A committed edit can create a vocabulary candidate and a Casual/Clear style example.

The local JSON database stores:

- raw transcript;
- plugin output;
- final edited text;
- Casual or Clear profile;
- timestamp;
- learned rule confidence and usage metadata.

It stores at most 500 transcript records. Surrounding text used for the current rewrite is never persisted. Casing fixes activate immediately; other vocabulary rules need two matching observations by default. Numeric edits are excluded from automatic rules. A learned-rule toast includes Undo.

Data lives under:

```text
~/Library/Application Support/TypeWhisper/PluginData/com.raysun.typewhisper.adaptive-dictionary/
```

## Build, verify, and install

Requirements: TypeWhisper in `/Applications`, Xcode 16+, XcodeGen, Swift 6, and Xcode's Metal toolchain.

```sh
xcodebuild -downloadComponent MetalToolchain
swift test
scripts/build.sh
scripts/verify.sh
scripts/install.sh
```

After the model is downloaded, the release bundle can be exercised without recording audio:

```sh
scripts/run-plugin-harness.sh process \
  "Can you look at this React component I think focus on the state management" \
  "com.todesktop.230313mzl4w4u92"
```

The build reads the installed TypeWhisper version and compiles against the matching SDK tag. MLX Swift LM is pinned to upstream commit `09deb8c4`, which contains the regression-tested shared-KV loader fix required by the current July 2026 E4B weights. The installed plugin appears as **Adaptive Dictation** while retaining its existing stable plugin identifier and correction database.

This project is licensed under GPL-3.0-only.
