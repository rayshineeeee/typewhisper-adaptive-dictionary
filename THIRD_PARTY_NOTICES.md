# Third-party notices

The release bundle includes a copy of this notice, the Adaptive Dictation GPL license, and the full license text for each linked runtime dependency.

## TypeWhisper Gemma 4 plugin

`Sources/AdaptiveDictionaryPlugin/LocalGemmaRuntime.swift` adapts model download, tokenizer bridging, and MLX container loading from TypeWhisper's `Gemma4Plugin` at tag `v1.5.1`. Adaptive Dictation changed that code for its post-processing policy, plugin-owned storage, recording-triggered loading, idle unloading, and settings.

- Source: https://github.com/TypeWhisper/typewhisper-mac/tree/v1.5.1/TypeWhisperPluginSDK/Plugins/Gemma4Plugin
- License: GPL-3.0-only
- Copyright: TypeWhisper contributors
- Adaptive Dictation modifications: Copyright (C) 2026 Ray Sun

## MLX Swift LM

Adaptive Dictation links MLX Swift LM at commit `09deb8c4e9056fcd76b60718bb50325d1730572b` for local model inference.

- Source: https://github.com/ml-explore/mlx-swift-lm/tree/09deb8c4e9056fcd76b60718bb50325d1730572b
- License: MIT
- Copyright: 2024 ml-explore

## Swift Transformers

Adaptive Dictation links Swift Transformers at commit `2fa33e1f5e7131a7fc64c28e6d161dcec0d24820` for Hugging Face model download and tokenization.

- Source: https://github.com/huggingface/swift-transformers/tree/2fa33e1f5e7131a7fc64c28e6d161dcec0d24820
- License: Apache-2.0
- Copyright: 2022 Hugging Face SAS

## Gemma 4 model files

Model files are not part of this repository or plugin bundle. When a user clicks **Download & Load**, the plugin downloads the selected MLX conversion from Hugging Face into TypeWhisper's plugin-scoped data directory. The default repository is `mlx-community/gemma-4-e4b-it-4bit`; the smaller option is `mlx-community/gemma-4-e2b-it-4bit`.

The model files remain subject to the terms published on their current model cards. Users should review those terms before downloading. Adaptive Dictation does not redistribute the model files.
