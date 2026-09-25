import 'dart:async';
import 'dart:io';

import 'package:edgehead/edgehead_lib.dart';
import 'package:edgehead/egamebook/elements/elements.dart';
import 'package:edgehead_tui/edgehead_theme.dart';
import 'package:edgehead_tui/music_playback.dart';
import 'package:edgehead_tui/tui_presenter.dart';
import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  if (args.length.isOdd) {
    stderr.writeln(
        'Usage: dart run bin/edgehead_tui.dart [--image-dir PATH] [--audio-dir PATH] [--theme PATH]');
    exitCode = 64;
    return;
  }
  var imageDirectory =
      Directory.fromUri(Platform.script.resolve('../assets/images/'));
  var audioDirectory =
      Directory.fromUri(Platform.script.resolve('../assets/audio/'));
  var themeFile = File.fromUri(Platform.script.resolve('../theme.json'));
  for (var index = 0; index < args.length; index += 2) {
    switch (args[index]) {
      case '--image-dir':
        imageDirectory = Directory(args[index + 1]).absolute;
      case '--audio-dir':
        audioDirectory = Directory(args[index + 1]).absolute;
      case '--theme':
        themeFile = File(args[index + 1]).absolute;
      default:
        stderr.writeln('Unknown option: ${args[index]}');
        exitCode = 64;
        return;
    }
  }
  final EdgeheadTheme theme;
  try {
    theme = EdgeheadTheme.load(themeFile);
  } on FormatException catch (error) {
    stderr.writeln('Invalid theme: ${error.message}');
    exitCode = 65;
    return;
  } on FileSystemException catch (error) {
    stderr.writeln('Could not read theme: ${error.message}');
    exitCode = 66;
    return;
  }
  final presenter = TuiPresenter();
  await presenter.initialize(EdgeheadGame(randomizeAfterPlayerChoice: false));
  try {
    await runApp(
      EdgeheadScreen(
        presenter: presenter,
        imageDirectory: imageDirectory,
        audioDirectory: audioDirectory,
        theme: theme,
      ),
      enableHotReload: false,
    );
  } finally {
    presenter.close();
  }
}

class EdgeheadScreen extends StatefulComponent {
  const EdgeheadScreen({
    required this.presenter,
    required this.imageDirectory,
    required this.audioDirectory,
    required this.theme,
    super.key,
  });

  final TuiPresenter presenter;
  final Directory imageDirectory;
  final Directory audioDirectory;
  final EdgeheadTheme theme;

  @override
  State<EdgeheadScreen> createState() => _EdgeheadScreenState();
}

class _EdgeheadScreenState extends State<EdgeheadScreen> {
  final AutoScrollController _storyScroll = AutoScrollController();
  final ScrollController _choiceScroll = ScrollController();
  MusicPlayback? _musicPlayback;
  StoryMusic? _musicCue;
  final Map<String, String?> _asciiArtCache = {};
  List<StoryEntry> _shownPreviews = [];
  List<StoryEntry?>? _clearingPreviews;
  bool _quitting = false;

  TuiPresenter get game => component.presenter;
  EdgeheadTheme get theme => component.theme;

  @override
  void initState() {
    super.initState();
    game.onChanged = () {
      final previews = game.activePreviews;
      final music = game.activeMusic;
      if (!identical(_musicCue, music)) {
        _musicPlayback?.stop();
        _musicCue = music;
        if (music == null) {
          _musicPlayback = null;
        } else {
          final playback = MusicPlayback(
            track: File.fromUri(
                component.audioDirectory.uri.resolve(music.source)),
            limitSpectrumRedraws: () =>
                (Platform.environment['TERM_PROGRAM'] ?? '')
                    .toLowerCase()
                    .contains('iterm') &&
                game.activePreviews.whereType<StoryImage>().any(
                    (image) => !image.source.toLowerCase().endsWith('.txt')),
            onChanged: () {
              if (mounted && identical(_musicCue, music)) setState(() {});
            },
          );
          _musicPlayback = playback;
          unawaited(playback.start());
        }
      }
      if (_clearingPreviews == null &&
          _shownPreviews
              .whereType<StoryImage>()
              .any((oldImage) => !previews.contains(oldImage))) {
        // Native image cleanup runs after Nocterm paints the next frame.
        // Keep empty slots for one frame before resizing the preview column.
        _clearingPreviews = _shownPreviews
            .map<StoryEntry?>((preview) =>
                preview is StoryImage && !previews.contains(preview)
                    ? null
                    : preview)
            .toList();
        TerminalBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _clearingPreviews = null;
              _shownPreviews = game.activePreviews;
            });
          }
        });
      } else if (_clearingPreviews == null) {
        _shownPreviews = previews;
      }
      if (mounted) setState(() {});
    };
    scheduleMicrotask(game.startBook);
  }

  @override
  void dispose() {
    _musicPlayback?.stop();
    game.onChanged = null;
    _storyScroll.dispose();
    _choiceScroll.dispose();
    super.dispose();
  }

  bool _handleKey(KeyboardEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKey.keyQ ||
        (key == LogicalKey.keyC && event.isControlPressed)) {
      unawaited(_quit());
      return true;
    }
    if (key == LogicalKey.pageUp) {
      _storyScroll.scrollUp(_storyScroll.viewportDimension);
      return true;
    }
    if (key == LogicalKey.pageDown) {
      _storyScroll.scrollDown(_storyScroll.viewportDimension);
      return true;
    }
    if (game.awaitingReroll) {
      if (key == LogicalKey.keyY || key == LogicalKey.enter) {
        game.reroll(true);
        return true;
      }
      if (key == LogicalKey.keyN || key == LogicalKey.escape) {
        game.reroll(false);
        return true;
      }
      return false;
    }
    if (game.choices != null) {
      if (key == LogicalKey.arrowDown || key == LogicalKey.keyJ) {
        game.moveChoice(1);
        _showSelectedChoice();
        return true;
      }
      if (key == LogicalKey.arrowUp || key == LogicalKey.keyK) {
        game.moveChoice(-1);
        _showSelectedChoice();
        return true;
      }
      if (key == LogicalKey.enter || key == LogicalKey.space) {
        game.choose();
        return true;
      }
      if (key == LogicalKey.keyS || key == LogicalKey.keyF) {
        game.choose(forceResult: key == LogicalKey.keyS);
        return true;
      }
    }
    return false;
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _musicPlayback?.stopAndWait();
    } finally {
      shutdownApp();
    }
  }

  void _showSelectedChoice() {
    TerminalBinding.instance.addPostFrameCallback((_) {
      if (mounted && game.choices != null) {
        _choiceScroll.ensureIndexVisible(index: game.selectedChoice);
      }
    });
  }

  Component _panel(String title, Component body, {Color? color}) {
    final panelColor = color ?? theme['story'];
    return Container(
      padding: const EdgeInsets.only(left: 1, right: 1, top: 1),
      decoration: BoxDecoration(
        border: BoxBorder.all(color: panelColor),
        title: BorderTitle(
          text: title,
          style: TextStyle(color: panelColor, fontWeight: FontWeight.bold),
        ),
      ),
      child: body,
    );
  }

  Component _storyPanel() {
    return _panel(
      'STORY',
      ListView.builder(
        controller: _storyScroll,
        itemCount: game.story.length,
        itemBuilder: (context, index) {
          final entry = game.story[index];
          return Container(
            padding: const EdgeInsets.only(bottom: 1),
            child: switch (entry) {
              StoryText(:final text) =>
                Text(text, style: TextStyle(color: theme['text'])),
              StoryImage(:final description) => Text(
                  '[Illustration: $description]',
                  style: TextStyle(color: theme['illustration']),
                ),
              StoryMusic(:final title) => Text(
                  '♫ $title',
                  style: TextStyle(color: theme['music']),
                ),
            },
          );
        },
      ),
    );
  }

  String? _readAsciiArt(File file) {
    return _asciiArtCache.putIfAbsent(file.path, () {
      try {
        if (file.lengthSync() > 64 * 1024) return null;
        final lines = file
            .readAsStringSync()
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll('\t', '    ')
            .split('\n');
        while (lines.isNotEmpty && lines.first.trim().isEmpty) {
          lines.removeAt(0);
        }
        while (lines.isNotEmpty && lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        if (lines.isEmpty) return null;
        final indent = lines
            .where((line) => line.trim().isNotEmpty)
            .map((line) => line.length - line.trimLeft().length)
            .reduce((left, right) => left < right ? left : right);
        return lines
            .map((line) => line.length > indent ? line.substring(indent) : '')
            .join('\n');
      } on FileSystemException {
        return null;
      } on FormatException {
        return null;
      }
    });
  }

  Component _asciiIllustration(
      File file, int width, int height, Component fallback) {
    final art = _readAsciiArt(file);
    if (art == null) return fallback;
    if (width <= 0 || height <= 0) return const SizedBox.shrink();

    final lines = art.split('\n');
    final artWidth = lines.fold<int>(
        0, (widest, line) => line.length > widest ? line.length : widest);
    final left = artWidth > width ? (artWidth - width) ~/ 2 : 0;
    final top = lines.length > height ? (lines.length - height) ~/ 2 : 0;
    final visible = lines.skip(top).take(height).map((line) {
      if (line.length <= left) return '';
      final end = line.length < left + width ? line.length : left + width;
      return line.substring(left, end);
    }).join('\n');

    return Text(
      visible,
      style: TextStyle(color: theme['illustration']),
      softWrap: false,
      overflow: TextOverflow.clip,
    );
  }

  Component _storyImage(
      String description, String source, int width, int height) {
    final uri = Uri.tryParse(source);
    final fallback = Text('[Illustration: $description] ($source)',
        style: TextStyle(color: theme['muted']));
    final Component image;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      // Nocterm's image widget is experimental, but it owns terminal redraws.
      // ignore: experimental_member_use
      image = Image.network(
        source,
        height: height,
        fit: BoxFit.contain,
        placeholder: Text('Loading illustration: $description'),
        errorWidget: fallback,
      );
    } else {
      if (uri != null && uri.hasScheme && uri.scheme != 'file') {
        return fallback;
      }
      final file = File.fromUri(component.imageDirectory.uri.resolve(source));
      if (!file.existsSync()) return fallback;
      if (file.path.toLowerCase().endsWith('.txt')) {
        return _asciiIllustration(file, width, height, fallback);
      }
      // ignore: experimental_member_use
      image = Image.file(
        file.path,
        height: height,
        fit: BoxFit.contain,
        placeholder: Text('Loading illustration: $description'),
        errorWidget: fallback,
      );
    }
    return image;
  }

  Component _statusPanel() {
    final stamina = game.stats['stamina']?.toString() ?? '-';
    final sanity = game.stats['sanity']?.toString() ?? '-';
    return _panel(
      'STATUS',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stamina  $stamina', style: TextStyle(color: theme['text'])),
          Text('Sanity   $sanity', style: TextStyle(color: theme['text'])),
          if (game.ending != null)
            Text(game.ending!, style: TextStyle(color: theme['warning'])),
          if (game.error != null)
            Text(game.error!, style: TextStyle(color: theme['error'])),
        ],
      ),
      color: theme['status'],
    );
  }

  Component _illustrationPanel(StoryImage illustration) {
    return _panel(
      'ILLUSTRATION',
      LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.bottomCenter,
          child: _storyImage(
            illustration.description,
            illustration.source,
            constraints.maxWidth.floor(),
            constraints.maxHeight.floor(),
          ),
        ),
      ),
      color: theme['illustration'],
    );
  }

  Component _musicPanel(StoryMusic music) {
    final playback = _musicPlayback;
    return _panel(
      'MUSIC',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('♫ ${music.title.toUpperCase()}',
              style: TextStyle(color: theme['music'])),
          const SizedBox(height: 1),
          Expanded(
            child: playback?.message == null
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.floor();
                      final height = constraints.maxHeight.floor();
                      final bars = (width ~/ 2).clamp(1, 24);
                      final levels =
                          playback?.levels ?? List<int>.filled(24, 0);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var row = 0; row < height; row++)
                            Text(
                              List.generate(bars, (index) {
                                final source =
                                    ((index + 0.5) * levels.length / bars)
                                        .floor();
                                final threshold =
                                    ((height - row) * 1000 / height).round();
                                return levels[source] >= threshold
                                    ? '█ '
                                    : '  ';
                              }).join(),
                              style: TextStyle(
                                  color: row < height ~/ 3
                                      ? theme['spectrumHigh']
                                      : theme['spectrumLow']),
                            ),
                        ],
                      );
                    },
                  )
                : Text(playback!.message!),
          ),
          Text('mpv · cava', style: TextStyle(color: theme['muted'])),
        ],
      ),
      color: theme['music'],
    );
  }

  Component _interactionPanel() {
    final machine = game.slotMachine;
    if (machine != null) {
      return _panel(
        'ROLL',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(machine.rollReason, style: TextStyle(color: theme['text'])),
            Text(
                'Chance ${((game.activeRollChance ?? machine.probability) * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: theme['text'])),
            const SizedBox(height: 1),
            Text(game.rollDisplay ?? 'Preparing roll...',
                style: TextStyle(color: theme['warning'])),
            if (game.awaitingReroll)
              Text(
                  'Reroll? Y / N  (${machine.rerollEffectDescription ?? 'use a resource'})',
                  style: TextStyle(color: theme['text'])),
          ],
        ),
        color: theme['roll'],
      );
    }

    final block = game.choices;
    if (block == null) {
      return _panel(
          'CHOICES',
          Text(
              game.ending == null
                  ? 'The story is unfolding...'
                  : 'Press Q to quit.',
              style: TextStyle(color: theme['text'])));
    }
    return _panel(
      'CHOICES',
      ListView.builder(
        controller: _choiceScroll,
        itemCount: block.choices.length,
        itemBuilder: (context, index) {
          final Choice choice = block.choices[index];
          final selected = index == game.selectedChoice;
          final label = choice.commandPath.join(' > ');
          final chance = '${(choice.successChance * 100).round()}%';
          return Container(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '${selected ? '>' : ' '} ${index + 1}. $label  ($chance)',
              style: TextStyle(
                color: selected ? theme['selected'] : theme['text'],
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
      color: theme['choices'],
    );
  }

  @override
  Component build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: _handleKey,
      child: Container(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('EDGEHEAD',
                style: TextStyle(
                    color: theme['title'], fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Expanded(
              flex: 3,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final List<StoryEntry?> previews =
                      _clearingPreviews ?? _shownPreviews;
                  final capacity = (constraints.maxHeight.floor() - 8) ~/ 12;
                  final visibleCount = capacity < 0
                      ? 0
                      : capacity > previews.length
                          ? previews.length
                          : capacity;
                  final visiblePreviews =
                      previews.skip(previews.length - visibleCount).toList();
                  final showPreview = visiblePreviews.isNotEmpty;
                  final sidebarWidth = showPreview
                      ? (constraints.maxWidth * 0.36)
                          .clamp(30.0, 50.0)
                          .toDouble()
                      : 23.0;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _storyPanel()),
                      const SizedBox(width: 1),
                      SizedBox(
                        width: sidebarWidth,
                        child: showPreview
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(height: 8, child: _statusPanel()),
                                  for (final preview in visiblePreviews) ...[
                                    const SizedBox(height: 1),
                                    Expanded(
                                      flex: preview is StoryImage &&
                                              preview.source
                                                  .toLowerCase()
                                                  .endsWith('.txt')
                                          ? 2
                                          : 1,
                                      child: switch (preview) {
                                        StoryImage image =>
                                          _illustrationPanel(image),
                                        StoryMusic music => _musicPanel(music),
                                        _ => _panel(
                                            'ILLUSTRATION',
                                            const SizedBox(),
                                            color: theme['illustration'],
                                          ),
                                      },
                                    ),
                                  ],
                                ],
                              )
                            : _statusPanel(),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 1),
            Expanded(flex: 2, child: _interactionPanel()),
            const SizedBox(height: 1),
            Text(
                '↑↓/J K choose   Enter select   PgUp/PgDn story   S/F force roll   Q quit',
                style: TextStyle(color: theme['muted'])),
          ],
        ),
      ),
    );
  }
}
