import 'dart:async';
import 'dart:io';

import 'package:edgehead/edgehead_lib.dart';
import 'package:edgehead/egamebook/elements/elements.dart';
import 'package:edgehead_tui/tui_presenter.dart';
import 'package:nocterm/nocterm.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && (args.length != 2 || args.first != '--image-dir')) {
    stderr.writeln('Usage: dart run bin/edgehead_tui.dart [--image-dir PATH]');
    exitCode = 64;
    return;
  }
  final imageDirectory = args.isEmpty
      ? Directory.fromUri(Platform.script.resolve('../assets/images/'))
      : Directory(args[1]).absolute;
  final presenter = TuiPresenter();
  await presenter.initialize(EdgeheadGame(randomizeAfterPlayerChoice: false));
  try {
    await runApp(
      EdgeheadScreen(presenter: presenter, imageDirectory: imageDirectory),
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
    super.key,
  });

  final TuiPresenter presenter;
  final Directory imageDirectory;

  @override
  State<EdgeheadScreen> createState() => _EdgeheadScreenState();
}

class _EdgeheadScreenState extends State<EdgeheadScreen> {
  final AutoScrollController _storyScroll = AutoScrollController();
  final ScrollController _choiceScroll = ScrollController();

  TuiPresenter get game => component.presenter;

  @override
  void initState() {
    super.initState();
    game.onChanged = () {
      if (mounted) setState(() {});
    };
    scheduleMicrotask(game.startBook);
  }

  @override
  void dispose() {
    game.onChanged = null;
    _storyScroll.dispose();
    _choiceScroll.dispose();
    super.dispose();
  }

  bool _handleKey(KeyboardEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKey.keyQ ||
        (key == LogicalKey.keyC && event.isControlPressed)) {
      shutdownApp();
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

  void _showSelectedChoice() {
    TerminalBinding.instance.addPostFrameCallback((_) {
      if (mounted && game.choices != null) {
        _choiceScroll.ensureIndexVisible(index: game.selectedChoice);
      }
    });
  }

  Component _panel(String title, Component body, {Color color = Colors.blue}) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(border: BoxBorder.all(color: color)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Expanded(child: body),
        ],
      ),
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
              StoryText(:final text) => Text(text),
              StoryImage(:final description, :final source) =>
                _storyImage(description, source),
            },
          );
        },
      ),
    );
  }

  Component _storyImage(String description, String source) {
    final uri = Uri.tryParse(source);
    final fallback = Text('[Illustration: $description] ($source)');
    final Component image;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      // Nocterm's image widget is experimental, but it owns terminal redraws.
      // ignore: experimental_member_use
      image = Image.network(
        source,
        height: 12,
        placeholder: Text('Loading illustration: $description'),
        errorWidget: fallback,
      );
    } else {
      if (uri != null && uri.hasScheme && uri.scheme != 'file') {
        return fallback;
      }
      final file = File.fromUri(component.imageDirectory.uri.resolve(source));
      if (!file.existsSync()) return fallback;
      // ignore: experimental_member_use
      image = Image.file(
        file.path,
        height: 12,
        placeholder: Text('Loading illustration: $description'),
        errorWidget: fallback,
      );
    }
    return SizedBox(height: 12, child: image);
  }

  Component _statusPanel() {
    final stamina = game.stats['stamina']?.toString() ?? '-';
    final sanity = game.stats['sanity']?.toString() ?? '-';
    return _panel(
      'STATUS',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stamina  $stamina'),
          Text('Sanity   $sanity'),
          const SizedBox(height: 1),
          if (game.ending != null)
            Text(game.ending!,
                style: const TextStyle(color: Colors.brightYellow)),
          if (game.error != null)
            Text(game.error!, style: const TextStyle(color: Colors.brightRed)),
        ],
      ),
      color: Colors.cyan,
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
            Text(machine.rollReason),
            Text(
                'Chance ${((game.activeRollChance ?? machine.probability) * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 1),
            Text(game.rollDisplay ?? 'Preparing roll...',
                style: const TextStyle(color: Colors.brightYellow)),
            if (game.awaitingReroll)
              Text(
                  'Reroll? Y / N  (${machine.rerollEffectDescription ?? 'use a resource'})'),
          ],
        ),
        color: Colors.yellow,
      );
    }

    final block = game.choices;
    if (block == null) {
      return _panel(
          'CHOICES',
          Text(game.ending == null
              ? 'The story is unfolding...'
              : 'Press Q to quit.'));
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
                color: selected ? Colors.brightYellow : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        },
      ),
      color: Colors.yellow,
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
            const Text('EDGEHEAD',
                style: TextStyle(
                    color: Colors.brightCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 1),
            Expanded(
              flex: 3,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _storyPanel()),
                  const SizedBox(width: 1),
                  SizedBox(width: 23, child: _statusPanel()),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Expanded(flex: 2, child: _interactionPanel()),
            const SizedBox(height: 1),
            const Text(
                '↑↓/J K choose   Enter select   PgUp/PgDn story   S/F force roll   Q quit',
                style: TextStyle(color: Colors.brightBlack)),
          ],
        ),
      ),
    );
  }
}
