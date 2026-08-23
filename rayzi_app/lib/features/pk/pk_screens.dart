import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

/// PK battle state polled from /pk/battles/:id with dragon stage rendering.
class PkBattleView extends StatefulWidget {
  const PkBattleView({super.key, required this.battleId});
  final String battleId;

  @override
  State<PkBattleView> createState() => _PkBattleViewState();
}

class _PkBattleViewState extends State<PkBattleView> {
  Map<String, dynamic>? _battle;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await ApiService.get('/pk/battles/${widget.battleId}');
      if (!mounted) return;
      setState(() => _battle = response.data['data']);
      final status = _battle?['status'];
      if (status == 'ended' || status == 'forfeited') _timer?.cancel();
    } catch (_) {}
  }

  int get _secondsLeft {
    if (_battle == null) return 0;
    final started = DateTime.tryParse(_battle!['started_at'] ?? '');
    if (started == null) return 0;
    final dur = (_battle!['duration_seconds'] ?? 300) as int;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (dur - elapsed).clamp(0, dur);
  }

  Widget _side(int side) {
    final b = _battle ?? const <String, dynamic>{};
    final score = (b[side == 1 ? 'score_1' : 'score_2'] ?? 0) as num;
    final stage = (b[side == 1 ? 'dragon_stage_1' : 'dragon_stage_2'] ?? 0) as num;
    const labels = ['🥚', '🐣', '🐉', '🐲', '🔥🐉'];
    final s = stage.toInt().clamp(0, 4);
    return Expanded(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(labels[s], style: TextStyle(fontSize: 56.sp)),
        SizedBox(height: 8.h),
        Text('$score',
            style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold)),
        Text('Side $side', style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final winnerId = _battle?['winner_id'];
    final ended = _battle != null && (_battle!['status'] != 'active');
    return Scaffold(
      appBar: AppBar(
        title: const Text('PK Battle'),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16.w),
            child: Center(
              child: Text('${(_secondsLeft / 60).floor()}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _battle == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              Row(children: [_side(1),
                Container(width: 2.w, color: Colors.white24),
                _side(2)]),
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: EdgeInsets.all(10.r),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('VS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp)),
                ),
              ),
              if (ended)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: EdgeInsets.all(20.h),
                    padding: EdgeInsets.all(16.r),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Battle over!',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.sp)),
                      SizedBox(height: 6.h),
                      Text(winnerId == null ? 'Draw!' : 'Winner decided by gift points 🏆',
                          style: TextStyle(fontSize: 13.sp)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

/// "PK Battle" button shown on the live-host toolbar.
class PkQueueButton extends StatefulWidget {
  const PkQueueButton({super.key, required this.streamId});
  final String streamId;

  @override
  State<PkQueueButton> createState() => _PkQueueButtonState();
}

class _PkQueueButtonState extends State<PkQueueButton> {
  bool _queueing = false;
  bool _matched = false;

  Future<void> _startOrCancel() async {
    setState(() => _queueing = true);
    try {
      if (_queueingActive && !_matched) {
        await ApiService.delete('/pk/queue');
        if (!mounted) return;
        setState(() { _queueingActive = false; });
      } else {
        final response = await ApiService.post('/pk/queue', data: {'stream_id': widget.streamId});
        final matched = response.data['data']?['matched'] == true;
        if (!mounted) return;
        if (matched) {
          setState(() { _queueingActive = false; _matched = true; });
          final battle = response.data['data']['battle'];
          Navigator.pushNamed(context, '/pk-battle', arguments: {'id': battle['id']}).then((_) => setState(() => _matched = false));
        } else {
          setState(() => _queueingActive = true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PK error: $e')));
    } finally {
      if (mounted) setState(() => _queueing = false);
    }
  }

  bool _queueingActive = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _queueing ? null : _startOrCancel,
      icon: Icon(_queueingActive ? Icons.close : Icons.sports_kabaddi, size: 18.r),
      label: Text(_matched ? 'In battle!' : _queueingActive ? 'Cancel' : 'PK Battle',
          style: TextStyle(fontSize: 12.sp)),
    );
  }
}
