# LocalWhisper

LocalWhisper is a small macOS menu-bar dictation injector for Claude, Codex, and OpenCode.

When enabled, it listens while a supported coding agent window is active, transcribes detected speech locally with `openai-whisper`, and types the result into that window. It follows the same guardrail as `slapmac`: if Claude/Codex/OpenCode is not active, it refuses to inject text.

## Requirements

- macOS 14+
- Swift toolchain
- CMake

```bash
make setup-native
```

`setup-native` downloads and builds vendored `whisper.cpp` static libraries, then downloads the GGML base English model. The native path records WAV directly, so ffmpeg is not needed for LocalWhisper's own recordings.

The old Python/OpenAI Whisper backend is still available as a fallback with `make setup`. Python fallback assets are not bundled by default; set `LOCALWHISPER_BUNDLE_PYTHON=1` when running `make app` or `make install` if you want them included.

## Run

```bash
make run
```

Use the menu-bar icon, then choose **Dictate Now**.

## Behavior

The **Enabled** menu item is the arming switch. When it is on:

- If Claude, Codex, OpenCode, or a supported terminal running one of those CLIs is focused, LocalWhisper listens for speech.
- If it hears speech, it records until about `0.8s` of silence, transcribes, types the text, optionally presses Return, then listens again.
- If **Use Last Target When Focus Changes** is on, it remembers the last supported target and reactivates it before typing. This lets you click another window while dictating back into the terminal or agent you last selected.
- If sticky target mode is off and no supported target is focused, it waits and checks again instead of recording or injecting text.
- **Dictate Now** still works as a one-shot manual trigger.

Menu controls:

- **Sensitivity**: higher values detect quieter speech.
- **Start Delay**: minimum recording time before silence can stop the capture.
- **Stop Delay**: silence duration required to finish an utterance.

Voice commands:

- `stop listening`, `stop dictation`, `disable dictation`, `turn off listening`: disables LocalWhisper and stops re-arming.
- `enable sticky target`, `disable sticky target`, `toggle sticky target`: controls whether focus returns to the last target.
- `press return`, `do not press return`, `toggle submit`: controls whether Return is sent after typing.

Voice commands are only treated as commands when the whole utterance is a short matching phrase. Longer sentences are typed normally.

## Install As App

```bash
make install
open /Applications/LocalWhisper.app
```

If `.venv` and `.models` exist when you run `make app` or `make install`, they are copied into the app bundle so the installed app can run without shell environment variables.

The app needs:

- Microphone permission for recording
- Accessibility permission for typing into the focused app

## Supported Targets

LocalWhisper injects only when the focused app is Claude, Claude Code, Codex, OpenCode, or a supported terminal with a `claude`, `codex`, or `opencode` process running.

Supported terminals: Terminal, iTerm2, Ghostty, Warp, Alacritty, kitty, WezTerm, Hyper.

## Settings

Environment variables:

- `LOCALWHISPER_BACKEND`: `whisper.cpp` or `python`, default auto-detect
- `LOCALWHISPER_LANGUAGE`: Whisper language, default `en` for `whisper.cpp`, `auto` for Python fallback
- `LOCALWHISPER_WHISPER_CLI`: path to `whisper-cli`
- `LOCALWHISPER_CPP_MODEL`: path to a GGML whisper.cpp model
- `LOCALWHISPER_CPP_MODEL_NAME`: model filename under `.models/whisper.cpp`, default `ggml-base.en.bin`
- `LOCALWHISPER_MODEL`: Python Whisper model name, default `base`
- `LOCALWHISPER_PYTHON`: Python executable, default `python3`
- `LOCALWHISPER_MODEL_DIR`: model cache directory, default `./.models/whisper` for the project helper

If `.venv/bin/python3` exists in the app bundle or project directory, the app uses it automatically.
