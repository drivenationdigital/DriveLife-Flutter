import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/guess_api.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:drivelife/routes.dart';
import 'package:drivelife/theme/dl_type.dart';
import 'package:drivelife/widgets/points/points_reward.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Guess the car.
///
/// One puzzle a day, four options, one guess, locked in. Opens at 7am,
/// closes at 7pm, and the answer is revealed to everybody at once.
///
/// The server never sends the answer before close, so there is nothing
/// in this file that could leak it — `game.answer` is simply null until
/// the game is over.
class GuessScreen extends StatefulWidget {
  /// Which tab to open on. 0 play, 1 leaderboard.
  ///
  /// The result notification deep-links to the leaderboard, because the
  /// result is why it was sent — opening on the puzzle would show a
  /// game that is already over.
  final int initialTab;

  const GuessScreen({super.key, this.initialTab = 0});

  @override
  State<GuessScreen> createState() => _GuessScreenState();
}

class _GuessScreenState extends State<GuessScreen>
    with SingleTickerProviderStateMixin {
  static const Color _ink = Color(0xFF111113);
  static const Color _panel = Color(0xFF1E1E21);

  late final TabController _tabs = TabController(
    length: 2,
    initialIndex: widget.initialTab.clamp(0, 1),
    vsync: this,
  );

  GuessGame? _today;
  List<GuessGame> _history = const [];

  List<GuessRank> _board = const [];
  int _myCorrect = 0;
  int? _myRank;
  String _scope = 'worldwide';

  bool _loading = true;
  bool _sending = false;

  /// Finished games whose answer this person has asked to see.
  ///
  /// Per screen, not persisted. Reopening offers the reveal again,
  /// which is right: the pause before tapping is the only tension the
  /// game has left once the clock has passed 7pm.
  final Set<int> _revealed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    final results = await Future.wait([
      GuessAPI.today(),
      GuessAPI.history(),
      GuessAPI.leaderboard(scope: _scope),
    ]);

    if (!mounted) return;

    final board =
        results[2] as ({List<GuessRank> entries, int correct, int? rank});

    setState(() {
      _today = results[0] as GuessGame?;
      _history = results[1] as List<GuessGame>;
      _board = board.entries;
      _myCorrect = board.correct;
      _myRank = board.rank;
      _loading = false;
    });
  }

  Future<void> _loadBoard() async {
    final board = await GuessAPI.leaderboard(scope: _scope);
    if (!mounted) return;

    setState(() {
      _board = board.entries;
      _myCorrect = board.correct;
      _myRank = board.rank;
    });
  }

  Future<void> _guess(int choice) async {
    final game = _today;
    if (game == null || _sending || game.hasPlayed || !game.isOpen) return;

    setState(() => _sending = true);

    final updated = await GuessAPI.play(gameId: game.id, choice: choice);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (updated != null) _today = updated;
    });

    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that guess. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // No reward here, win or lose. The answer is not known until 7pm —
    // showing anything celebratory now would either be a lie or a tell.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Locked in. The answer is revealed at 7pm.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        elevation: 0,
        title: const Text('Guess the car'),
        centerTitle: true,
      ),
      body: _loading
          ? _skeleton(theme)
          : Column(
              children: [
                _switcher(theme),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [_playTab(theme), _boardTab(theme)],
                  ),
                ),
              ],
            ),
    );
  }

  /// Grey blocks in the shape of what is coming.
  ///
  /// A spinner says "wait" and nothing else. Blocks the size of the
  /// real card say what is being waited for, and — because they occupy
  /// the same space — the page does not jump when the data lands.
  ///
  /// Deliberately not animated. A shimmer on a load that usually takes
  /// 300ms draws more attention than the wait deserves, and the shapes
  /// are doing the work.
  Widget _skeleton(ThemeProvider theme) {
    Widget block(double height, {double? width, double radius = 12}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // The two pills.
        Row(
          children: [
            Expanded(child: block(48, radius: 999)),
            const SizedBox(width: 10),
            Expanded(child: block(48, radius: 999)),
          ],
        ),
        const SizedBox(height: 14),

        // The game card: photo, prompt, four options, footer. Dark,
        // because the real one is — a white skeleton followed by a
        // black card is a flash, not a transition.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(children: [_dark(70, 16), const Spacer(), _dark(84, 16)]),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: _dark(double.infinity, double.infinity, radius: 12),
              ),
              const SizedBox(height: 18),
              _dark(120, 16),
              const SizedBox(height: 14),
              for (var row = 0; row < 2; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _dark(double.infinity, 62)),
                    const SizedBox(width: 10),
                    Expanded(child: _dark(double.infinity, 62)),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 28),
        block(24, width: 180),
        const SizedBox(height: 16),

        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: 18),
          Row(
            children: [
              block(48, width: 64, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(12, width: 60, radius: 6),
                    const SizedBox(height: 6),
                    block(14, width: 140, radius: 6),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// A block for use INSIDE the dark card, where #EDEDED would glare.
  Widget _dark(double width, double height, {double radius = 8}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  /// Play / Leaderboard, as two pills.
  ///
  /// Not a TabBar: these are two whole views rather than slices of one
  /// list, and a pill pair says "choose a mode" where an underline says
  /// "filter what is below".
  Widget _switcher(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabs.index = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tabs.index == i ? _ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _tabs.index == i ? _ink : theme.dividerColor,
                        width: 1.4,
                      ),
                    ),
                    child: Text(
                      i == 0 ? 'Play' : 'Leaderboard',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: _tabs.index == i
                            ? Colors.white
                            : theme.textColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Play ───────────────────────────────────────────────────────────

  Widget _playTab(ThemeProvider theme) {
    return RefreshIndicator(
      onRefresh: _load,
      color: theme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          if (_today == null) _noGame(theme) else _gameCard(theme, _today!),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 28),
            DlHeading('Previous 7 days', fontSize: 22, color: theme.textColor),
            const SizedBox(height: 8),
            for (final game in _history) _historyRow(theme, game),
          ],
        ],
      ),
    );
  }

  Widget _noGame(ThemeProvider theme) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.directions_car_outlined,
            size: 38,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          const DlHeading('No game today', fontSize: 22, color: Colors.white),
          const SizedBox(height: 6),
          Text(
            'Check back tomorrow morning.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _gameCard(ThemeProvider theme, GuessGame game) {
    return Container(
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _prettyDate(game.date),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  game.isClosed ? 'Closed' : 'Closes 7pm',
                  style: TextStyle(fontSize: 14.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: _puzzleOrReveal(theme, game),
              ),
            ),
          ),

          const SizedBox(height: 18),
          Center(child: _prompt(theme, game)),
          const SizedBox(height: 14),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 10),
                  // IntrinsicHeight is what makes the stretch legal.
                  //
                  // CrossAxisAlignment.stretch tells a Row to force its
                  // children to the full cross-axis extent. Inside a
                  // Column in a ListView that extent is UNBOUNDED, so
                  // the Row handed its children a tight infinite
                  // height and BoxConstraints.debugAssertIsValid threw
                  // before anything painted.
                  //
                  // IntrinsicHeight measures the taller of the two
                  // options first and gives the Row that height, so
                  // stretch has something finite to stretch to. The
                  // alternative — dropping stretch — lets a two-line
                  // option like "Mercedes SLR McLaren" sit taller than
                  // the one beside it, which is the ragged pair the
                  // mock does not have.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col > 0) const SizedBox(width: 10),
                          Expanded(child: _option(theme, game, row * 2 + col)),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A2A2E))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    !game.isClosed
                        ? 'Answer revealed at 7pm'
                        : _revealed.contains(game.id)
                        ? 'Answer: ${game.answer ?? '—'}'
                        : 'Tap reveal to see the answer',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ),
                Text(
                  '+${game.points} pts',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Show the answer, and pay off the suspense if they earned it.
  ///
  /// The reward fires HERE rather than when the guess was made,
  /// because at that point nobody — including the server — was willing
  /// to say whether it was right. This is the moment the person finds
  /// out, so it is the moment the points are worth celebrating.
  ///
  /// The points were already awarded server-side when the game
  /// settled; this is the telling, not the giving. PointsReward
  /// ignores a zero, so a wrong answer simply shows nothing.
  Future<void> _reveal(GuessGame game) async {
    setState(() => _revealed.add(game.id));

    if (game.myCorrect != true) return;

    // Let the reveal land first. Firing both in the same frame means
    // the overlay covers the photograph the person just asked to see.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    await PointsReward.show(
      context,
      points: game.points,
      reason: 'For guessing the car on ${_prettyDate(game.date)}',
    );
  }

  /// The puzzle photo, a Reveal button, or the car itself.
  ///
  /// Three states in one slot, which is what makes the reveal feel
  /// like something happening rather than a second picture appearing
  /// further down the page.
  Widget _puzzleOrReveal(ThemeProvider theme, GuessGame game) {
    if (!game.isClosed) return _photo(game.image);

    if (_revealed.contains(game.id)) {
      // Falls back to the puzzle shot when no reveal photo was
      // scheduled — a game can run with one image, and an empty frame
      // after tapping Reveal reads as broken.
      final url = game.revealImage.trim().isNotEmpty
          ? game.revealImage
          : game.image;

      return _photo(url);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // The puzzle shot stays underneath, blurred. A flat grey panel
        // would lose the sense that there is a specific photograph
        // about to be shown.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: _photo(game.image),
        ),
        const ColoredBox(color: Colors.black38),
        Center(
          child: Material(
            color: theme.primaryColor,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _reveal(game),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 19,
                      color: Colors.white,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'Reveal the answer',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _prompt(ThemeProvider theme, GuessGame game) {
    final shown = _revealed.contains(game.id);

    // "You got it right" IS the result, so it waits for the reveal too.
    final text = switch ((game.isClosed, game.hasPlayed)) {
      (true, true) =>
        shown
            ? (game.myCorrect == true ? 'You got it right' : 'Not this time')
            : 'The results are in',
      (true, false) => 'You did not play today',
      (false, true) => 'Locked in — back at 7pm',
      (false, false) => 'Pick one below',
    };

    final colour = shown && game.hasPlayed
        ? (game.myCorrect == true
              ? const Color(0xFF4CAF50)
              : Colors.grey.shade500)
        : theme.primaryColor;

    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: colour,
      ),
    );
  }

  /// One of the four.
  ///
  /// After close it colours itself: green for the right answer, red for
  /// a wrong one the user picked. Before close nothing is coloured —
  /// the only state is "chosen", because any other colour would be
  /// telling them something the server has deliberately withheld.
  Widget _option(ThemeProvider theme, GuessGame game, int index) {
    if (index >= game.options.length) return const SizedBox.shrink();

    // Gated on the REVEAL, not merely on the game being closed.
    //
    // Colouring the right answer green the moment the clock passes 7pm
    // gives it away before the person has tapped Reveal, which is the
    // one piece of theatre this screen has.
    final shown = _revealed.contains(game.id);

    final chosen = game.myChoice == index;
    final isAnswer = shown && game.answerIndex == index;
    final wrongPick = shown && chosen && !isAnswer;

    final border = isAnswer
        ? const Color(0xFF4CAF50)
        : wrongPick
        ? const Color(0xFFE53935)
        : chosen
        ? theme.primaryColor
        : const Color(0xFF3A3A3E);

    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: game.isOpen && !game.hasPlayed && !_sending
            ? () => _guess(index)
            : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: border,
              width: chosen || isAnswer ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            game.options[index],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyRow(ThemeProvider theme, GuessGame game) {
    final played = game.hasPlayed;
    final right = game.myCorrect == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _photo(game.image, width: 64, height: 48),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _prettyDate(game.date),
                  style: TextStyle(fontSize: 13, color: theme.subtextColor),
                ),
                Text(
                  game.answer ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: theme.textColor,
                  ),
                ),
                Text(
                  _guessedLabel(game),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: theme.subtextColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                !played ? 'No guess' : (right ? 'Correct' : 'Wrong'),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: right ? theme.primaryColor : theme.subtextColor,
                ),
              ),
              Text(
                right ? '+${game.points} pts' : '0 pts',
                style: TextStyle(fontSize: 13, color: theme.subtextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Leaderboard ────────────────────────────────────────────────────

  Widget _boardTab(ThemeProvider theme) {
    return RefreshIndicator(
      onRefresh: _loadBoard,
      color: theme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: DlHeading(
                  'Leaderboard',
                  fontSize: 24,
                  color: theme.textColor,
                ),
              ),
              _scopePicker(theme),
            ],
          ),
          const SizedBox(height: 10),

          // Said whenever today is still running, board or no board.
          // Without it somebody who guessed correctly an hour ago sees
          // a number that has not moved and assumes it is broken.
          if (_resultsPending) _pendingNote(theme),

          if (_board.isEmpty)
            _emptyBoard(theme)
          else
            for (final row in _board) _boardRow(theme, row),

          // Your own line, when you are not already on the board. Being
          // 214th is still information; being absent is not.
          if (_myRank != null && !_board.any((r) => r.isMe)) ...[
            Divider(color: theme.dividerColor),
            _myRow(theme),
          ],
        ],
      ),
    );
  }

  /// Whether today's game is still open.
  ///
  /// The leaderboard deliberately ignores a game until it closes — a
  /// count that ticks up the moment you guess tells you that you were
  /// right, twelve hours early. So while today is running, the
  /// standings are yesterday's and the screen should say so.
  bool get _resultsPending => _today != null && !_today!.isClosed;

  Widget _pendingNote(ThemeProvider theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: 17,
            color: theme.primaryColor,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "Today's results are pending. Standings update when the "
              'answer is revealed at 7pm.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: theme.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// An empty board means two completely different things.
  ///
  /// Before any game has closed it means the results are not in; after
  /// one has, it means nobody got it right. Saying "nobody has guessed
  /// right yet" on the first evening is simply false — everybody who
  /// guessed is waiting, not wrong.
  Widget _emptyBoard(ThemeProvider theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(
              _resultsPending
                  ? Icons.hourglass_empty_rounded
                  : Icons.emoji_events_outlined,
              size: 34,
              color: theme.dividerColor,
            ),
            const SizedBox(height: 12),
            Text(
              _resultsPending ? 'Results pending' : 'Nobody on the board yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                _resultsPending
                    ? 'The first standings appear once today closes at 7pm.'
                    : 'Nobody has guessed right yet. Be the first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: theme.subtextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scopePicker(ThemeProvider theme) {
    return PopupMenuButton<String>(
      initialValue: _scope,
      onSelected: (scope) {
        if (scope == _scope) return;
        setState(() => _scope = scope);
        _loadBoard();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'worldwide', child: Text('Worldwide')),
        PopupMenuItem(value: 'country', child: Text('My country')),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scope == 'country' ? 'My country' : 'Worldwide',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 20, color: theme.textColor),
          ],
        ),
      ),
    );
  }

  Widget _boardRow(ThemeProvider theme, GuessRank entry) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.viewProfile,
        arguments: {'userId': '${entry.userId}', 'username': entry.username},
      ),
      child: Container(
        color: entry.isMe
            ? theme.primaryColor.withValues(alpha: 0.07)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: entry.rank <= 3
                      ? theme.primaryColor
                      : theme.subtextColor,
                ),
              ),
            ),
            _avatar(entry.avatar, entry.bestName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.isMe ? 'You' : entry.bestName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.textColor,
                    ),
                  ),
                  if (entry.country.isNotEmpty)
                    Text(
                      entry.country,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: theme.subtextColor,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.correct}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.textColor,
                  ),
                ),
                Text(
                  'correct',
                  style: TextStyle(fontSize: 13, color: theme.subtextColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _myRow(ThemeProvider theme) {
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.07),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$_myRank',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: theme.subtextColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'You',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.textColor,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_myCorrect',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: theme.textColor,
                ),
              ),
              Text(
                'correct',
                style: TextStyle(fontSize: 13, color: theme.subtextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(String url, String name) {
    const size = 42.0;

    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFE8E8E8),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A8A8A),
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFFE8E8E8),
        ),
        errorWidget: (_, _, _) => Container(
          width: size,
          height: size,
          color: const Color(0xFFE8E8E8),
        ),
      ),
    );
  }

  /// A photograph, or a grey box when there is no URL.
  ///
  /// CachedNetworkImage does NOT treat an empty string as "no image" —
  /// it tries to fetch it and throws "No host specified in URI", which
  /// takes the whole screen down rather than leaving one grey
  /// rectangle. Every other screen in this app checks first; this one
  /// did not, which is what crashed it.
  Widget _photo(String url, {double? width, double? height}) {
    if (url.trim().isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(Icons.directions_car_outlined, color: Colors.white54),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (_, _) => Container(
        width: width,
        height: height,
        color: const Color(0xFFEDEDED),
      ),
      errorWidget: (_, _, _) => Container(
        width: width,
        height: height,
        color: const Color(0xFFEDEDED),
        child: const Center(
          child: Icon(Icons.broken_image, color: Colors.white54),
        ),
      ),
    );
  }

  /// "You guessed: Ferrari Enzo", safely.
  ///
  /// my_choice is an index into options, and the two arrive from the
  /// server as separate fields — so nothing guarantees the index is in
  /// range. An old game whose options were edited after somebody played
  /// it is enough to put it out, and an out-of-range index is a
  /// RangeError that kills the build rather than one odd-looking row.
  static String _guessedLabel(GuessGame game) {
    final choice = game.myChoice;

    if (choice == null) return 'You did not play';
    if (choice < 0 || choice >= game.options.length) {
      return 'You guessed';
    }

    return 'You guessed: ${game.options[choice]}';
  }

  /// "30 Oct" from "2026-10-30".
  static String _prettyDate(String iso) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final date = DateTime.tryParse(iso);
    if (date == null) return iso;

    return '${date.day} ${months[date.month - 1]}';
  }
}
