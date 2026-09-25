import 'dart:async';
import 'dart:math';

import 'package:edgehead/edgehead_lib.dart';
import 'package:edgehead/egamebook/commands/commands.dart';
import 'package:edgehead/egamebook/elements/elements.dart';
import 'package:edgehead/egamebook/presenter.dart';

sealed class StoryEntry {
  const StoryEntry();
}

class StoryText extends StoryEntry {
  const StoryText(this.text);

  final String text;
}

class StoryImage extends StoryEntry {
  const StoryImage(this.description, this.source);

  final String description;
  final String source;
}

class StoryMusic extends StoryEntry {
  const StoryMusic(this.title, this.source);

  final String title;
  final String source;
}

class TuiPresenter extends Presenter<EdgeheadGame> {
  static final RegExp _mediaCue = RegExp(
    r'!\[([^\]]*)\]\(([^)\s]+)\)|\[music:\s*([^\]]+)\]\(([^)\s]+)\)|\[(illustration|music|close):\s*([^\]]+)\]',
    caseSensitive: false,
  );

  final Random _rollRandom = Random();
  final Random _animationRandom = Random();

  final List<StoryEntry> story = [];
  final Map<String, int> stats = {};
  final List<StoryEntry> _activePreviews = [];

  List<StoryEntry> get activePreviews => List.unmodifiable(_activePreviews);

  StoryMusic? get activeMusic {
    for (final preview in _activePreviews.reversed) {
      if (preview is StoryMusic) return preview;
    }
    return null;
  }

  void Function()? onChanged;
  ChoiceBlock? choices;
  SlotMachine? slotMachine;
  String? rollDisplay;
  double? activeRollChance;
  String? error;
  String? ending;
  bool rolling = false;
  bool awaitingReroll = false;
  bool _closed = false;
  int selectedChoice = 0;
  bool? _forcedResult;

  void _changed() => onChanged?.call();

  void _appendStory(String text) {
    if (text.trim().isEmpty) return;
    var start = 0;
    for (final match in _mediaCue.allMatches(text)) {
      _appendStoryText(text.substring(start, match.start));
      if (match.group(1) != null) {
        final illustration = StoryImage(match.group(1)!, match.group(2)!);
        story.add(illustration);
        _activePreviews.removeWhere((preview) => preview is StoryImage);
        _activePreviews.add(illustration);
      } else if (match.group(3) != null) {
        final music = StoryMusic(match.group(3)!.trim(), match.group(4)!);
        story.add(music);
        _activePreviews.removeWhere((preview) => preview is StoryMusic);
        _activePreviews.add(music);
      } else {
        final kind = match.group(5)!.toLowerCase();
        final value = match.group(6)!.trim();
        switch (kind) {
          case 'illustration':
            final illustration = StoryImage(value, value);
            story.add(illustration);
            _activePreviews.add(illustration);
          case 'music':
            final title = value
                .split('/')
                .last
                .replaceFirst(RegExp(r'\.[^.]+$'), '')
                .replaceAll('_', ' ');
            final music = StoryMusic(title, value);
            story.add(music);
            _activePreviews.removeWhere((preview) => preview is StoryMusic);
            _activePreviews.add(music);
          case 'close':
            switch (value.toLowerCase()) {
              case 'illustration':
                _activePreviews.removeWhere((preview) => preview is StoryImage);
              case 'music':
                _activePreviews.removeWhere((preview) => preview is StoryMusic);
              case 'all':
                _activePreviews.clear();
              default:
                _appendStoryText(match.group(0)!);
            }
        }
      }
      start = match.end;
    }
    _appendStoryText(text.substring(start));
    while (story.length > 200) {
      story.removeAt(0);
    }
    _changed();
  }

  void _appendStoryText(String text) {
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) story.add(StoryText(trimmed));
  }

  void moveChoice(int delta) {
    final count = choices?.choices.length ?? 0;
    if (count == 0) return;
    selectedChoice = (selectedChoice + delta).clamp(0, count - 1);
    _changed();
  }

  void choose({bool? forceResult}) {
    final block = choices;
    if (block == null || block.choices.isEmpty) return;
    final choice = block.choices[selectedChoice];
    choices = null;
    _forcedResult = forceResult;
    _appendStory('> ${choice.commandSentence}');
    book!.accept(PickChoice((b) => b..choice = choice.toBuilder()));
    _changed();
  }

  void reroll(bool accepted) {
    final machine = slotMachine;
    if (!awaitingReroll || machine == null) return;
    awaitingReroll = false;
    if (accepted) {
      final rerollChance = 1 - pow(1 - machine.probability, 2).toDouble();
      unawaited(_roll(rerollChance, wasRerolled: true));
    } else {
      _finishRoll(false, wasRerolled: false);
    }
  }

  Future<void> _roll(double probability, {required bool wasRerolled}) async {
    rolling = true;
    activeRollChance = probability;
    rollDisplay = 'Rolling against ${(probability * 100).toStringAsFixed(1)}%';
    _changed();

    // This is the draw that decides the outcome. Animation uses a separate
    // random source, so decorative frames cannot change the result.
    final draw = _forcedResult == null
        ? _rollRandom.nextDouble()
        : (_forcedResult! ? 0.0 : 1.0);
    _forcedResult = null;
    for (var frame = 0; frame < 12; frame++) {
      if (_closed) return;
      rollDisplay =
          'Rolling  ${(_animationRandom.nextDouble() * 100).toStringAsFixed(1).padLeft(5)} '
          '/ ${(probability * 100).toStringAsFixed(1)}';
      _changed();
      await Future<void>.delayed(Duration(milliseconds: 35 + frame * 9));
    }
    if (_closed) return;

    final success = draw < probability;
    rolling = false;
    rollDisplay = '${(draw * 100).toStringAsFixed(1)} ${success ? '<' : '>='} '
        '${(probability * 100).toStringAsFixed(1)}  '
        '${success ? 'SUCCESS' : 'FAILURE'}';
    _changed();

    if (!success && !wasRerolled && slotMachine!.rerollable) {
      awaitingReroll = true;
      _changed();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!_closed) _finishRoll(success, wasRerolled: wasRerolled);
  }

  void _finishRoll(bool success, {required bool wasRerolled}) {
    final display = rollDisplay;
    if (display != null) _appendStory('Roll: $display');
    slotMachine = null;
    rollDisplay = null;
    activeRollChance = null;
    rolling = false;
    awaitingReroll = false;
    _changed();
    book!.accept(ResolveSlotMachine((b) => b
      ..result = success ? SlotResult.success : SlotResult.failure
      ..wasRerolled = wasRerolled));
  }

  @override
  void addChoiceBlock(ChoiceBlock block) {
    if (block.choices.length == 1 && block.choices.single.isImplicit) {
      book!.accept(
          PickChoice((b) => b..choice = block.choices.single.toBuilder()));
      return;
    }
    choices = block;
    selectedChoice = 0;
    _changed();
  }

  @override
  void addSlotMachine(SlotMachine machine) {
    slotMachine = machine;
    final forced = _forcedResult;
    if (forced != null) {
      _forcedResult = null;
      rollDisplay = forced ? 'Forced success' : 'Forced failure';
      _finishRoll(forced, wasRerolled: false);
      return;
    }
    unawaited(_roll(machine.probability, wasRerolled: false));
  }

  @override
  void addText(TextOutput text) => _appendStory(text.markdownText);

  @override
  void addCustomElement(ElementBase element) {
    if (element is StatInitialization) {
      stats[element.name] = element.initialValue;
      _changed();
      return;
    }
    if (element is StatUpdate) {
      stats[element.name] = element.newValue;
      _changed();
      return;
    }
    super.addCustomElement(element);
  }

  @override
  void addWin(WinGame win) {
    ending = 'YOU WIN';
    _activePreviews.clear();
    _appendStory(win.markdownText);
  }

  @override
  void addLose(LoseGame lose) {
    ending = 'GAME OVER';
    _activePreviews.clear();
    _appendStory(lose.markdownText);
  }

  @override
  void addError(ErrorElement errorElement) {
    error = errorElement.message;
    _changed();
  }

  @override
  void addLog(LogElement log) {}

  @override
  void addSavegameBookmark(SaveGame savegame) {}

  @override
  void beforeElement() {}

  @override
  void close() {
    _closed = true;
    onChanged = null;
    super.close();
  }
}
