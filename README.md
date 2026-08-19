# Adaptive Dictation for TypeWhisper

Local dictation cleanup that sits on top of [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac). It removes verbal debris, handles self-corrections, adds structure when it helps, and learns vocabulary from the edits you make after dictation. Transcript processing and learning stay on your Mac.

Adaptive Dictation is a post-processor, not a transcription engine. Keep using Parakeet, Whisper, or another TypeWhisper transcription plugin for speech recognition.

## Why I made this

Accurate transcription still leaves a gap between the words I said and the message I meant to send. I wanted dictation that could understand "never mind, scratch that," remove an unhelpful "like" without flattening my voice, turn real lists into bullets, and remember names I repeatedly correct.

The paid dictation apps solve part of that problem with cloud processing and a subscription. I wanted the same useful layer to run locally, remain inspectable, and improve from my edits without sending private messages, notes, journal entries, or prompts to a remote service. This plugin is that layer.

## Install

Requirements:

- An Apple Silicon Mac running macOS 14 or newer
- TypeWhisper 1.5 or newer

1. [Download `AdaptiveDictionaryPlugin.zip`](https://github.com/rayshineeeee/typewhisper-adaptive-dictionary/releases/latest/download/AdaptiveDictionaryPlugin.zip).
2. Open **TypeWhisper > Settings > Integrations**.
3. Click **Install from File...** and select the downloaded ZIP. You do not need to unzip it.
4. Enable **Adaptive Dictation**, then open its settings.

The lightweight cleanup and adaptive vocabulary work immediately. For ambiguous self-corrections, spoken formatting, and longer passages, turn on **Use local semantic cleanup when wording is ambiguous**, then click **Download & Load**.

The default Gemma 4 E4B model is a one-time download of about 5.2 GB and uses about 4.5 GB of memory while loaded. It begins loading when recording starts and unloads after ten idle minutes. A smaller E2B option is available in the plugin settings.

For the cleanest pipeline, disable TypeWhisper's separate **Filler Words** post-processor so the same transcript is not cleaned twice. Vocabulary boosting in your transcription model can remain enabled.

## What it changes

- Removes obvious fillers such as `um` and `uh`, while leaving quoted speech alone.
- Collapses accidental stutters but preserves intentional emphasis and grammatical repetition.
- Understands soft self-corrections such as "actually, wait" and "scratch that."
- Uses bullets for genuine lists, tasks, steps, or an explicit spoken formatting command.
- Preserves names, numbers, quoted text, URLs, code identifiers, slang, profanity, and intended meaning.
- Keeps questions as questions. It never answers a prompt or acts as an assistant.
- Learns vocabulary corrections from the text you commit after dictation.

There are two writing profiles:

| Profile | Where it applies | Output |
| --- | --- | --- |
| Casual | Messages and WeChat | Lowercase opening, natural punctuation, no final period |
| Clear | Everywhere else | Normal casing and punctuation, conservative structure |

Notes and Notion use Clear. Both profiles use the same conservative cleanup strength.

## How processing works

1. Apply confirmed vocabulary corrections stored on this Mac.
2. Run fast, deterministic cleanup and select the Casual or Clear profile.
3. Decide whether the transcript needs semantic repair.
4. If it does, use the optional local Gemma 4 model.
5. Reject any rewrite that answers the speaker, drops protected content, changes numbers, alters URLs or code, or rewrites too much.
6. Fall back to the deterministic result on a timeout, model error, or rejected rewrite.

Simple dictation never waits for the model. Short model-gated dictation has a two-second deadline; long passages have a ten-second ceiling. A late result is never inserted after the fallback.

## How learning works

After TypeWhisper inserts a transcript, Adaptive Dictation watches only that inserted range. If you correct it and then press Return or Tab, change focus, switch apps, or leave it for 30 seconds, the plugin compares its output with your final text.

Casing corrections can activate immediately. Other vocabulary corrections require two matching observations by default. Numeric edits never become automatic rules. A notification appears when a rule is learned and includes an Undo action.

Learning is global for vocabulary. Style examples are shared within Casual or Clear, not tied to an individual app. You can inspect, disable, undo, or delete learned rules from the **Learning** tab.

## Privacy and local data

Inference is local. There is no telemetry, remote rewrite service, or cloud fallback. Network access is used only when you explicitly download a selected model from Hugging Face.

The local database stores the raw transcript, plugin output, final edited text, selected profile, timestamp, and learned-rule metadata. It keeps at most 500 transcript records. Surrounding text can be used as temporary local context for the current rewrite, but is never persisted.

Data and downloaded model files live under:

```text
~/Library/Application Support/TypeWhisper/PluginData/com.raysun.typewhisper.adaptive-dictionary/
```

## Build from source

You need TypeWhisper in `/Applications`, Xcode 16 or newer, XcodeGen, Swift 6, and Xcode's Metal toolchain.

```sh
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
git clone https://github.com/rayshineeeee/typewhisper-adaptive-dictionary.git
cd typewhisper-adaptive-dictionary
scripts/install.sh
```

The install script builds against the SDK version matching the installed TypeWhisper app, backs up an existing Adaptive Dictation bundle, installs the new bundle, enables it, and restarts TypeWhisper.

Useful development commands:

```sh
swift test
scripts/verify.sh
scripts/package-release.sh
scripts/run-plugin-harness.sh process \
  "Can you look at this React component I think focus on the state management" \
  "com.todesktop.230313mzl4w4u92"
```

MLX Swift LM is pinned to commit `09deb8c4`; Swift Transformers is pinned to commit `2fa33e1f`. The built bundle includes the required third-party license texts and never includes model weights.

## Project status

Version 1.1.1 is the first public release. It has been exercised with TypeWhisper 1.5.1 on Apple Silicon. Community marketplace submission is tracked separately; until TypeWhisper publishes a signed community build, install the ZIP from this repository.

Issues and focused pull requests are welcome. When reporting cleanup behavior, include the input, expected output, actual output, app category, and whether the local model was used. Remove private content first.

Adaptive Dictation is an independent community project and is not affiliated with or endorsed by TypeWhisper.

## License

Adaptive Dictation is free software under [GPL-3.0-only](LICENSE). Source adapted from TypeWhisper remains under GPL-3.0. MLX Swift LM and Swift Transformers retain their respective MIT and Apache-2.0 terms. Model weights are downloaded separately and remain subject to the model publisher's terms. See [third-party notices](THIRD_PARTY_NOTICES.md).
