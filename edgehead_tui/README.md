# Edgehead TUI

A full-screen terminal interface for Edgehead. It uses the existing Dart game
without changing its rules or story files.

## Run

From this directory, run:

```sh
dart pub get
dart run bin/edgehead_tui.dart
```

Story passages can include Markdown images such as
`![Illustration of Darg](darg.png)`. The TUI shows a caption in the story and,
when space allows, opens a separate Illustration preview pane beneath Status.
The pane uses the terminal's image protocol (iTerm2 or Kitty, with a Unicode
fallback). A new image replaces the current preview. The sample goblin preview
closes when the first goblin dies. Put image files in `assets/images/`, or pass
another folder:

```sh
dart run bin/edgehead_tui.dart --image-dir /path/to/story/images
```

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
