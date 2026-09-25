#!/usr/bin/env bash
set -euo pipefail

tui_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
game_dir="$tui_dir/../edgehead"

if ! command -v dart >/dev/null 2>&1; then
  echo 'Dart is not on PATH. Install the Dart SDK or Flutter first.' >&2
  exit 127
fi

cd "$game_dir"
if [[ ! -f .dart_tool/package_config.json ]]; then
  dart pub get
fi

echo 'Compiling the latest .egb.txt story edits...'
dart run build_runner build --delete-conflicting-outputs

if [[ "${1:-}" == '--build-only' ]]; then
  echo 'Story compiled. Restart the TUI to load it.'
  exit 0
fi

cd "$tui_dir"
if [[ ! -f .dart_tool/package_config.json ]]; then
  dart pub get
fi

echo 'Starting Edgehead TUI with the updated story...'
exec dart run bin/edgehead_tui.dart "$@"
