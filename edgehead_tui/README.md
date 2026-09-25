# Edgehead TUI

A full-screen terminal interface for Edgehead. It uses the existing Dart game
without changing its rules or story files.

## Run

From this directory, run:

```sh
dart pub get
dart run bin/edgehead_tui.dart
```

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
