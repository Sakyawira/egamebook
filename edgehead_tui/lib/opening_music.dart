import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Plays the opening track and reads Cava's raw spectrum without writing to
/// the terminal. The TUI owns drawing the bars inside its preview pane.
class OpeningMusic {
  OpeningMusic({required this.track, required this.onChanged});

  final File track;
  final void Function() onChanged;

  List<int> levels = List<int>.filled(24, 0);
  String? message;

  Process? _player;
  Process? _cava;
  Directory? _configDirectory;
  String? _cavaError;
  bool _stopped = false;

  Future<void> start() async {
    if (!track.existsSync()) {
      message = 'Opening track missing: ${track.path}';
      onChanged();
      return;
    }

    try {
      final player = await Process.start('mpv', [
        '--no-config',
        '--no-video',
        '--no-terminal',
        '--loop-file=inf',
        '--volume=55',
        '--',
        track.path,
      ]);
      if (_stopped) {
        player.kill();
        return;
      }
      _player = player;
      unawaited(player.stdout.drain<void>());
      unawaited(player.stderr.drain<void>());
      unawaited(player.exitCode.then((_) {
        if (!_stopped) {
          message = 'Music player stopped';
          stop();
          onChanged();
        }
      }));
    } on ProcessException {
      message = 'Install mpv to play the opening music';
      onChanged();
      return;
    }

    final input = Platform.isMacOS
        ? 'method = coreaudio\nsource = tap'
        : Platform.isLinux
            ? 'method = pipewire\nsource = auto'
            : null;
    if (input == null) {
      message = 'Cava preview is available on macOS and Linux';
      onChanged();
      return;
    }

    try {
      final directory = await Directory.systemTemp.createTemp('edgehead-cava-');
      _configDirectory = directory;
      final config = File.fromUri(directory.uri.resolve('config'));
      await config.writeAsString('''
[general]
framerate = 24
bars = 24
sleep_timer = 0
[input]
$input
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
channels = mono
bar_delimiter = 59
frame_delimiter = 10
''');
      if (_stopped) return;

      final cava = await Process.start('cava', ['-p', config.path]);
      if (_stopped) {
        cava.kill();
        return;
      }
      _cava = cava;
      cava.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_readFrame);
      cava.stderr.transform(utf8.decoder).listen((output) {
        if (output.trim().isNotEmpty) {
          _cavaError = output.trim().split('\n').first;
        }
      });
      unawaited(cava.exitCode.then((_) {
        if (!_stopped) {
          message = _cavaError == null ? 'Cava stopped' : 'Cava: $_cavaError';
          onChanged();
        }
      }));
    } on ProcessException {
      message = 'Install cava to show the music visualizer';
      onChanged();
    } on FileSystemException {
      message = 'Could not start the music visualizer';
      onChanged();
    }
  }

  void _readFrame(String frame) {
    if (_stopped) return;
    final values = frame.split(';').where((value) => value.isNotEmpty).toList();
    if (values.length != levels.length) return;
    final parsed = values.map(int.tryParse).toList();
    if (parsed.any((value) => value == null)) return;
    levels = parsed.map((value) => value!.clamp(0, 1000)).toList();
    onChanged();
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _cava?.kill();
    _player?.kill();
    final directory = _configDirectory;
    if (directory != null) {
      unawaited(directory.delete(recursive: true).then<void>(
            (_) {},
            onError: (Object _) {},
          ));
    }
  }
}
