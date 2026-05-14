# LocalWhisper Ideas

## Voice Wake-Up While Disabled

Current behavior: voice commands are processed only after LocalWhisper records and transcribes an utterance. If the user says `stop listening`, the app disables recording, so it cannot hear `start listening` afterward.

Possible improvement: add a separate lightweight command-only listener that stays active while dictation is disabled.

Design notes:

- Keep full dictation disabled after `stop listening`.
- Run a low-cost wake listener that only accepts a small command set.
- Require explicit phrases such as `local whisper start listening` to avoid accidental reactivation.
- Consider Apple Speech framework for command-only recognition to avoid loading Whisper continuously.
- Alternatively keep a tiny Whisper model or VAD-plus-command path warm, but measure memory first.
- Add a menu toggle for command wake mode.

## Persistent Whisper Worker

Current behavior: Whisper launches per transcription, keeping idle memory low but adding latency.

Possible improvement: keep a Python worker alive while Enabled is on.

- Load the model once.
- Send audio file paths to the worker over stdin, a local socket, or HTTP.
- Expect roughly 650-700 MB extra RSS for the current `base` model.
- Add a menu setting for low-memory vs low-latency mode.

## Safer Sticky Target

Current behavior: sticky target reactivates the last supported app before typing.

Possible improvements:

- Show the remembered target name in the menu.
- Add a voice command to clear the remembered target.
- Detect when the terminal tab/window changes if macOS APIs allow it.
- Add an optional confirmation sound before typing into a sticky target.

## Command Feedback

Current behavior: commands silently change state except for debug logs.

Possible improvements:

- Play a short sound when `stop listening` is accepted.
- Use a different menu-bar icon for command-disabled vs fully disabled.
- Add notifications for voice commands when useful.
