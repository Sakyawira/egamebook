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

binary="$tui_dir/.dart_tool/edgehead_tui"
needs_compile=false
if [[ ! -x "$binary" ]]; then
  needs_compile=true
elif [[ "$tui_dir/pubspec.yaml" -nt "$binary" ||
        "$tui_dir/.dart_tool/package_config.json" -nt "$binary" ||
        "$game_dir/pubspec.yaml" -nt "$binary" ||
        "$game_dir/.dart_tool/package_config.json" -nt "$binary" ]]; then
  needs_compile=true
elif [[ -n "$(find "$tui_dir/bin" "$tui_dir/lib" "$game_dir/lib" \
    "$tui_dir/../egamebook_builder/lib" -type f -name '*.dart' \
    -newer "$binary" -print -quit)" ]]; then
  needs_compile=true
fi

if [[ "$needs_compile" == true ]]; then
  echo 'Compiling TUI executable (first run or story/code changed)...'
  dart compile exe bin/edgehead_tui.dart -o "$binary"
fi

echo 'Starting Edgehead TUI with the updated story...'
exec "$binary" "$@"
