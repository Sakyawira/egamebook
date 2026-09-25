# Edgehead TUI

A full-screen terminal interface for Edgehead. It uses the existing Dart game
and reads preview cues from its story files.

## Run

Clone the repository and run `./run_latest.sh` from its root, or run this from
`edgehead_tui/`:

```sh
./run_latest.sh
```

On CachyOS or Arch Linux, the launcher uses `sudo pacman -Syu --needed` to
install missing `dart`, `mpv`, and `cava` packages before compiling and starting
the game. Pacman asks you to approve its transaction. Dart then downloads the
project packages on first run. `--build-only` needs only Dart. On other systems,
install any missing tools yourself before running the launcher.

Story text controls preview panels with these cues:

```text
[Music: haunting_intro.m4a]
[Illustration: goblin.png]
[Close: Illustration]
[Close: Music]
```

Each Illustration cue opens another image panel. A new Music cue replaces the
current music panel and track. Illustration and Music panels can stay open
together. `[Close: Illustration]` closes all image panels, `[Close: Music]`
stops playback and removes Cava, and `[Close: All]` removes every preview.
The panels stack beneath Status when the terminal has enough height. File names
may contain spaces. Existing Markdown images such as `![Darg](darg.png)` still
work and replace earlier image panels; legacy music links also work.

After editing an `edgehead/assets/text/**/*.egb.txt` story file, quit the TUI
and run `./run_latest.sh` again to compile your latest local edits and start
the game.

Neovim highlighting and a `:EgbBuild` command for these story files are in
[`editor/nvim`](../editor/nvim/README.md). The command saves the open story,
compiles it, and reports errors in quickfix. Restart the TUI to load the result.

Use `./run_latest.sh --build-only` to compile without starting the TUI. The
script does not pull from Git or change your story files. The equivalent manual
build command, run from `edgehead/`, is:

```sh
dart run build_runner build --delete-conflicting-outputs
```

On the first launch, or after Dart source or generated story code changes, the
launcher compiles a TUI executable in `.dart_tool/`. Later launches reuse it,
so the game starts without `dart run` compiling the large story at startup.

For repeated edits, `dart run build_runner watch --delete-conflicting-outputs`
keeps the generated code up to date; the TUI still needs a restart to load it.

Music files are read from `assets/audio/`, and images from `assets/images/`.
The launcher checks for `mpv` and `cava` for music and the live spectrum. Cava reads audio
through CoreAudio tap on macOS or PipeWire on Linux. Images use the terminal's
image protocol (iTerm2 or Kitty, with a Unicode fallback). The bundled track
can be regenerated with `python3 tools/generate_intro.py` and `ffmpeg`.

To use another image directory:

```sh
dart run bin/edgehead_tui.dart --image-dir /path/to/story/images
```

Use `--audio-dir /path/to/music` to load music cues from another directory.

Colors are in `theme.json`. Edit its `#RRGGBB` values and restart the TUI, or
pass a different file with `--theme /path/to/theme.json`. Missing keys use the
built-in palette; the terminal still controls the background color.

The source repository contains image references but does not include their
artwork. A small sample `goblin.png`, rendered from `goblin.txt`, illustrates
the first goblin encounter. Other missing images show their description and
filename until artwork is supplied. Images with full HTTP(S) URLs are also
supported.

Use a terminal at least 80 columns wide for the two-panel layout.

| Key | Action |
| --- | --- |
| Up/Down or J/K | Move through choices |
| Enter or Space | Select a choice |
| Page Up/Page Down | Scroll the story |
| S/F | Select a choice and force the next roll to succeed/fail (playtesting) |
| Y/N | Accept or decline a reroll |
| Q or Ctrl-C | Quit |

The roll panel shows the actual random draw against the action's probability.
Animated frames are visual only. After a failed roll, the same reroll rules and
resource costs as the original CLI apply.

The terminal interface lives in a separate package so the original
`edgehead/bin/play.dart` entry point remains available.
