import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

// ---------------------------------------------------------------------------
// Mini-Games — three playable games that submit {game_key, score, moves} to
// POST /games/score. The server decides payout: implausible scores are
// rejected, per-session caps and daily limits are enforced server-side.
// ---------------------------------------------------------------------------

const List<Map<String, String>> kGames = [
  {'key': '2048', 'name': '2048 Puzzle', 'emoji': '🔢', 'desc': 'Merge tiles, chase 2048'},
  {'key': 'tic_tac_toe', 'name': 'Tic Tac Toe', 'emoji': '⭕', 'desc': 'Beat the AI to win'},
  {'key': 'memory_match', 'name': 'Memory Match', 'emoji': '🧠', 'desc': 'Match all pairs fast'},
];

class GamesHomeScreen extends StatelessWidget {
  const GamesHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mini-Games')),
      body: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: kGames.length,
        itemBuilder: (context, i) {
          final g = kGames[i];
          return Card(
            margin: EdgeInsets.only(bottom: 12.h),
            child: ListTile(
              leading: Text(g['emoji']!, style: TextStyle(fontSize: 28.sp)),
              title: Text(g['name']!, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
              subtitle: Text(g['desc']!, style: TextStyle(fontSize: 12.sp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/game-detail', arguments: g['key']),
            ),
          );
        },
      ),
    );
  }
}

class GameDetailScreen extends StatelessWidget {
  final String gameKey;
  const GameDetailScreen({super.key, required this.gameKey});

  @override
  Widget build(BuildContext context) {
    switch (gameKey) {
      case 'tic_tac_toe':
        return const TicTacToeGame();
      case 'memory_match':
        return const MemoryMatchGame();
      case '2048':
      default:
        return const Game2048();
    }
  }
}

/// Submits a finished session and surfaces the server's verdict (coins,
/// cap, or rejection). Returns the awarded coin amount (-1 on failure).
Future<int> submitGameScore(BuildContext context, String gameKey, int score, int moves) async {
  try {
    final res = await ApiService.post('/games/score', data: {
      'game_key': gameKey,
      'score': score,
      'moves': moves,
    });
    final data = res.data['data'] as Map<String, dynamic>;
    final coins = (data['coins_awarded'] as num?)?.toInt() ?? 0;
    if (!context.mounted) return coins;
    final capped = data['capped'] == true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(capped ? 'Daily limit reached' : '+$coins coins!'),
        content: Text(capped
            ? 'You played this game a lot today — this session paid 0 coins. Come back tomorrow!'
            : 'Score $score in $moves moves credited $coins coins.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return coins;
  } catch (e) {
    if (!context.mounted) return -1;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Score rejected: $e')));
    return -1;
  }
}

// ---------------------------------------------------------------------------
// 2048
// ---------------------------------------------------------------------------
class Game2048 extends StatefulWidget {
  const Game2048({super.key});
  @override
  State<Game2048> createState() => _Game2048State();
}

class _Game2048State extends State<Game2048> {
  List<List<int>> grid = [];
  int score = 0;
  int moves = 0;
  bool gameOver = false;
  bool submitted = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    grid = List.generate(4, (_) => List.filled(4, 0));
    score = 0;
    moves = 0;
    gameOver = false;
    submitted = false;
    _spawn();
    _spawn();
  }

  void _spawn() {
    final empty = <List<int>>[];
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        if (grid[r][c] == 0) empty.add([r, c]);
      }
    }
    if (empty.isEmpty) return;
    empty.shuffle();
    grid[empty.first[0]][empty.first[1]] = DateTime.now().millisecond % 10 == 0 ? 4 : 2;
  }

  bool _move(String dir) {
    var moved = false;
    final before = grid.map((r) => List<int>.from(r)).toList();

    List<int> collapse(List<int> line) {
      final vals = line.where((v) => v != 0).toList();
      final out = <int>[];
      var i = 0;
      while (i < vals.length) {
        if (i + 1 < vals.length && vals[i] == vals[i + 1]) {
          final merged = vals[i] * 2;
          score += merged;
          out.add(merged);
          i += 2;
        } else {
          out.add(vals[i]);
          i++;
        }
      }
      while (out.length < 4) {
        out.add(0);
      }
      return out;
    }

    if (dir == 'left' || dir == 'right') {
      for (var r = 0; r < 4; r++) {
        var line = grid[r].toList();
        if (dir == 'right') line = line.reversed.toList();
        line = collapse(line);
        if (dir == 'right') line = line.reversed.toList();
        grid[r] = line;
      }
    } else {
      for (var c = 0; c < 4; c++) {
        var line = [for (var r = 0; r < 4; r++) grid[r][c]];
        if (dir == 'down') line = line.reversed.toList();
        line = collapse(line);
        if (dir == 'down') line = line.reversed.toList();
        for (var r = 0; r < 4; r++) {
          grid[r][c] = line[r];
        }
      }
    }

    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        if (before[r][c] != grid[r][c]) moved = true;
      }
    }
    return moved;
  }

  bool get _noMovesLeft {
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        if (grid[r][c] == 0) return false;
        if (c < 3 && grid[r][c] == grid[r][c + 1]) return false;
        if (r < 3 && grid[r][c] == grid[r + 1][c]) return false;
      }
    }
    return true;
  }

  Future<void> _swipe(Offset v) async {
    if (gameOver) return;
    final dir = v.dx.abs() > v.dy.abs()
        ? (v.dx > 0 ? 'right' : 'left')
        : (v.dy > 0 ? 'down' : 'up');
    if (!_move(dir)) return;
    setState(() {
      moves++;
      _spawn();
      if (_noMovesLeft) gameOver = true;
    });
    if (gameOver && !submitted && mounted) {
      submitted = true;
      await submitGameScore(context, '2048', score, moves);
    }
  }

  Color _tileColor(int v) {
    const map = {
      2: Color(0xFFEEE4DA), 4: Color(0xFFEDE0C8), 8: Color(0xFFF2B179),
      16: Color(0xFFF59563), 32: Color(0xFFF67C5F), 64: Color(0xFFF65E3B),
      128: Color(0xFFEDCF72), 256: Color(0xFFEDCC61), 512: Color(0xFFEDC850),
      1024: Color(0xFFEDC53F), 2048: Color(0xFFEDC22E),
    };
    return map[v] ?? const Color(0xFF3C3A32);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2048')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  Text('SCORE', style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                  Text('$score', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold)),
                ]),
                Column(children: [
                  Text('MOVES', style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                  Text('$moves', style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold)),
                ]),
                ElevatedButton(onPressed: () => setState(_reset), child: const Text('New')),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onPanEnd: (d) => _swipe(d.velocity.pixelsPerSecond),
                child: Container(
                  width: 320.w,
                  height: 320.w,
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade100,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    mainAxisSpacing: 8.w,
                    crossAxisSpacing: 8.w,
                    children: [
                      for (var r = 0; r < 4; r++)
                        for (var c = 0; c < 4; c++)
                          Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tileColor(grid[r][c]),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Text(
                              grid[r][c] == 0 ? '' : '${grid[r][c]}',
                              style: TextStyle(
                                fontSize: grid[r][c] >= 1024 ? 18.sp : 22.sp,
                                fontWeight: FontWeight.bold,
                                color: grid[r][c] <= 4 ? Colors.black87 : Colors.white,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (gameOver)
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text('Game over · $score points',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            ),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tic-Tac-Toe vs simple AI. Win pays (server converts score 100 -> coins).
// ---------------------------------------------------------------------------
class TicTacToeGame extends StatefulWidget {
  const TicTacToeGame({super.key});
  @override
  State<TicTacToeGame> createState() => _TicTacToeGameState();
}

class _TicTacToeGameState extends State<TicTacToeGame> {
  List<String> board = List.filled(9, '');
  bool playerTurn = true;
  String status = 'Your turn (X)';
  bool done = false;
  int playerMoves = 0;
  int score = 0;
  bool submitted = false;

  static const wins = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
  ];

  String? _winner(List<String> b) {
    for (final w in wins) {
      if (b[w[0]].isNotEmpty && b[w[0]] == b[w[1]] && b[w[1]] == b[w[2]]) return b[w[0]];
    }
    return b.every((c) => c.isNotEmpty) ? 'draw' : null;
  }

  void _play(int i) {
    if (done || !playerTurn || board[i].isNotEmpty) return;
    setState(() {
      board[i] = 'X';
      playerMoves++;
      final w = _winner(board);
      if (w != null) {
        done = true;
        if (w == 'X') {
          score = 100;
          status = 'You win!';
        } else {
          score = 0;
          status = w == 'draw' ? 'Draw' : 'AI wins';
        }
      } else {
        playerTurn = false;
        status = 'AI thinking…';
      }
    });
    if (!done) Future.delayed(const Duration(milliseconds: 400), _aiMove);
  }

  void _aiMove() {
    if (done || !mounted) return;
    // Win if possible, block if needed, else center/corner preference.
    String? pickFor(String s) {
      for (final w in wins) {
        final vals = w.map((i) => board[i]).toList();
        if (vals.where((v) => v == s).length == 2 && vals.contains('')) {
          return w[vals.indexOf('')].toString();
        }
      }
      return null;
    }

    final idxStr = pickFor('O') ?? pickFor('X');
    int idx;
    if (idxStr != null) {
      idx = int.parse(idxStr);
    } else if (board[4].isEmpty) {
      idx = 4;
    } else {
      final corners = [0, 2, 6, 8].where((i) => board[i].isEmpty).toList();
      final rest = [for (var i = 0; i < 9; i++) i].where((i) => board[i].isEmpty).toList();
      idx = corners.isNotEmpty ? corners.first : rest.first;
    }

    setState(() {
      board[idx] = 'O';
      final w = _winner(board);
      if (w != null) {
        done = true;
        score = 0;
        status = w == 'draw' ? 'Draw' : 'AI wins';
      } else {
        playerTurn = true;
        status = 'Your turn (X)';
      }
    });

    if (done && !submitted && mounted) {
      submitted = true;
      submitGameScore(context, 'tic_tac_toe', score, playerMoves);
    }
  }

  void _reset() {
    setState(() {
      board = List.filled(9, '');
      playerTurn = true;
      done = false;
      status = 'Your turn (X)';
      playerMoves = 0;
      score = 0;
      submitted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tic Tac Toe')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Text(status, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          ),
          Center(
            child: SizedBox(
              width: 300.w,
              height: 300.w,
              child: GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 6.w,
                crossAxisSpacing: 6.w,
                children: [
                  for (var i = 0; i < 9; i++)
                    Material(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10.r),
                      child: InkWell(
                        onTap: () => _play(i),
                        child: Center(
                          child: Text(
                            board[i],
                            style: TextStyle(
                              fontSize: 40.sp,
                              fontWeight: FontWeight.bold,
                              color: board[i] == 'X' ? Colors.deepPurple : Colors.orange,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: _reset, child: const Text('New round')),
              SizedBox(width: 12.w),
              Text('Wins pay bonus coins',
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Memory Match — 6 pairs. Faster completion (fewer pair-flips) = higher score.
// ---------------------------------------------------------------------------
class MemoryMatchGame extends StatefulWidget {
  const MemoryMatchGame({super.key});
  @override
  State<MemoryMatchGame> createState() => _MemoryMatchGameState();
}

class _MemoryMatchGameState extends State<MemoryMatchGame> {
  static const emojis = ['🍎', '🚀', '🎧', '🐼', '⚽', '🌈'];
  late List<String> cards; // 12 entries (6 pairs)
  late List<bool> revealed;
  int firstPick = -1;
  int moves = 0; // completed pair-flips
  int matched = 0;
  bool lock = false;
  bool done = false;
  bool submitted = false;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    cards = [...emojis, ...emojis]..shuffle();
    revealed = List.filled(12, false);
    firstPick = -1;
    moves = 0;
    matched = 0;
    lock = false;
    done = false;
    submitted = false;
  }

  Future<void> _tap(int i) async {
    if (lock || done || revealed[i]) return;
    setState(() => revealed[i] = true);
    if (firstPick == -1) {
      firstPick = i;
      return;
    }
    final a = firstPick;
    firstPick = -1;
    lock = true;
    await Future.delayed(const Duration(milliseconds: 550), () {});
    if (!mounted) return;
    setState(() {
      moves++;
      if (cards[a] == cards[i]) {
        matched++;
        if (matched == 6) {
          done = true;
        }
      } else {
        revealed[a] = false;
        revealed[i] = false;
      }
      lock = false;
    });
    if (done && !submitted && mounted) {
      submitted = true;
      // Perfect game = 6 flips. Every extra flip costs 20 pts, floor 100.
      final score = (1000 - 20 * (moves - 6)).clamp(100, 1000);
      await submitGameScore(context, 'memory_match', score, moves);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Memory Match')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Text('Flips: $moves · Pairs: $matched/6',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 320.w,
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 10.w,
                  crossAxisSpacing: 10.w,
                  childAspectRatio: 0.9,
                  children: [
                    for (var i = 0; i < 12; i++)
                      Material(
                        color: revealed[i]
                            ? Colors.deepPurple.shade100
                            : Colors.deepPurple,
                        borderRadius: BorderRadius.circular(12.r),
                        child: InkWell(
                          onTap: () => _tap(i),
                          child: Center(
                            child: Text(
                              revealed[i] ? cards[i] : '?',
                              style: TextStyle(fontSize: 30.sp),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (done)
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text('Cleared in $moves flips!',
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            ),
          ElevatedButton(onPressed: () => setState(_reset), child: const Text('New game')),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}
