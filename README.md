[![Build status](https://github.com/filiph/egamebook/actions/workflows/dart.yml/badge.svg)](https://github.com/filiph/egamebook/actions/workflows/dart.yml)

Welcome to the code repository for the egamebook project.

This repository contains all the moving parts needed for running egamebook
campaigns, in one place, using the [monorepo][] approach. 

If you choose to play around with egamebook, you will probably spend 
most of your time in the `edgehead/` subdirectory. Edgehead is the canonical
example of an egamebook, and it provides a way of running the game
in terminal. Go read Edgehead's [README][] to learn more about playing,
playtesting, and developing Edgehead.

To start the full-screen Edgehead game from the repository root, run
`./run_latest.sh`. On CachyOS or Arch Linux it installs any missing Dart, mpv,
and Cava packages with pacman before building the story and starting the TUI.
See [Edgehead TUI](edgehead_tui/README.md) for details.

If you're thinking of building your own egamebook, the easiest way to start
is to make a copy of the `edgehead` subdirectory and start changing
the text files and the Dart files there.

If you're looking for more info about egamebook itself, visit [egamebook.com][].

To play the IFCOMP 2017 entry called _Insignificant Little Vermin_,
[click here][vermin].

[monorepo]: https://danluu.com/monorepo/
[README]: https://github.com/filiph/egamebook/tree/master/edgehead#edgehead-
[egamebook.com]: https://egamebook.com/
[vermin]: https://egamebook.com/vermin/

## Development

Most development happens inside the subfolders of this monorepo. 
But for CI, you'll need to use the Dart `mono_repo` package:

    dart pub global activate mono_repo

This installs the `mono_repo` command line tool.

To run all tests in the whole mono_repo (the tests that will be run
by Github Actions), use this command:

    mono_repo presubmit
