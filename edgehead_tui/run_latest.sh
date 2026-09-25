#!/usr/bin/env bash
set -euo pipefail

tui_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
game_dir="$tui_dir/../edgehead"

required=(dart)
if [[ "${1:-}" != '--build-only' ]]; then
  required+=(mpv cava)
fi

missing=()
for package in "${required[@]}"; do
  if ! command -v "$package" >/dev/null 2>&1; then
    missing+=("$package")
  fi
done

if (( ${#missing[@]} > 0 )); then
  if [[ "$(uname -s)" == Linux ]] && command -v pacman >/dev/null 2>&1; then
    if (( EUID == 0 )); then
      echo 'Run this script as your normal user; it will ask for sudo when packages are missing.' >&2
      exit 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
      echo 'sudo is required to install the missing packages: '"${missing[*]}" >&2
      exit 127
    fi
    echo 'Installing missing TUI dependencies: '"${missing[*]}"
    sudo pacman -Syu --needed "${missing[@]}"
  else
    echo 'Missing TUI dependencies: '"${missing[*]}" >&2
    echo 'Install them and run this script again.' >&2
    exit 127
  fi
fi

for package in "${required[@]}"; do
  if ! command -v "$package" >/dev/null 2>&1; then
    echo "$package is still not on PATH after installation." >&2
    exit 127
  fi
done

cd "$game_dir"
if [[ ! -f .dart_tool/package_config.json ]]; then
  dart pub get
fi

story_stamp="$game_dir/.dart_tool/edgehead_story_build.stamp"
story_generated="$game_dir/lib/writers_input.compiled.dart"
needs_story_build=false
if [[ "${1:-}" == '--build-only' || ! -f "$story_stamp" || ! -f "$story_generated" ]]; then
  needs_story_build=true
elif [[ "$game_dir/pubspec.yaml" -nt "$story_stamp" ||
        "$game_dir/pubspec.lock" -nt "$story_stamp" ||
        "$game_dir/build.yaml" -nt "$story_stamp" ||
        "$game_dir/.dart_tool/package_config.json" -nt "$story_stamp" ||
        "$tui_dir/../egamebook_builder/pubspec.yaml" -nt "$story_stamp" ]]; then
  needs_story_build=true
elif [[ -n "$(find "$game_dir/assets/text" "$game_dir/lib" \
    "$tui_dir/../egamebook_builder/lib" -type f -newer "$story_stamp" \
    -print -quit)" ]]; then
  needs_story_build=true
fi

if [[ "$needs_story_build" == true ]]; then
  echo 'Compiling the latest .egb.txt story edits...'
  dart run build_runner build --delete-conflicting-outputs
  touch "$story_stamp"
fi

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
