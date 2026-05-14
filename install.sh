#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$2"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "CarelessWhisper currently installs on macOS only."
fi

if ! xcode-select -p >/dev/null 2>&1; then
  fail "Xcode Command Line Tools are missing. Run: xcode-select --install"
fi

need_command swift "Swift is missing. Install Xcode Command Line Tools with: xcode-select --install"
need_command cmake "CMake is missing. Install it, for example: brew install cmake"
need_command curl "curl is missing."
need_command make "make is missing. Install Xcode Command Line Tools with: xcode-select --install"

printf 'Installing CarelessWhisper...\n'
make install

cat <<'EOF'

Installed:
  /Applications/CarelessWhisper.app

Next steps:
  1. Open /Applications/CarelessWhisper.app
  2. Grant Microphone permission when prompted.
  3. Grant Accessibility permission in System Settings -> Privacy & Security -> Accessibility.

EOF
