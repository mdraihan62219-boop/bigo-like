import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';
import '../../features/shared/decorated_widgets.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> _entries = [];
  String _type = 'gifters'; // gifters | hosts
  bool _rewardable = false;
  String _period = 'daily';
  bool _isLoading = true;

  static const _periods = ['daily', 'weekly', 'monthly', 'all'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/leaderboard', queryParameters: {
        'type': _type,
        'period': _period,
        'rewardable': _rewardable.toString(),
      });
      if (!mounted) return;
      setState(() {
        _entries = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top3 = _entries.take(3).toList();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leaderboard'),
          actions: [
            DropdownButton<String>(
              value: _period,
              underline: const SizedBox(),
              items: _periods
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) {
                setState(() => _period = v ?? 'daily');
                _load();
              },
            ),
            SizedBox(width: 16.w),
          ],
          bottom: TabBar(
            isScrollable: false,
            onTap: (i) {
              setState(() {
                _type = i < 2 ? 'gifters' : 'hosts';
                _rewardable = i == 1 || i == 3;
              });
              _load();
            },
            tabs: const [
              Tab(text: 'Gifters', icon: Icon(Icons.diamond_outlined)),
              Tab(text: 'Rewardable', icon: Icon(Icons.verified_outlined)),
              Tab(text: 'Hosts', icon: Icon(Icons.live_tv)),
              Tab(text: 'R. Hosts', icon: Icon(Icons.verified_user)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: _entries.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 200),
                        Center(child: Text('No leaderboard data yet')),
                      ])
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          if (index == 0 && top3.length > 1) {
                            return Column(children: [_buildPodium(top3), ..._buildRest()]);
                          }
                          if (index > 0 && index <= (top3.length - 1)) {
                            return const SizedBox.shrink();
                          }
                          return _buildTile(_entries[index], index);
                        },
                      ),
              ),
      ),
    );
  }

  List<Widget> _buildRest() {
    return [
      for (int i = 3; i < _entries.length; i++) _buildTile(_entries[i], i),
    ];
  }

  Widget _buildPodium(List<dynamic> top3) {
    Widget podiumSlot(dynamic entry, int slot) {
      // Layout order on the podium: 2nd, 1st, 3rd.
      final place = [1, 0, 2][slot];
      if (place >= top3.length) return const Expanded(child: SizedBox());
      final e = top3[place];
      final user = e['user'] as Map<String, dynamic>? ?? {};
      final ring = ProfileCosmetics.frameFor(
        (user['equipped_frame'] as Map<String, dynamic>?)?['tier'] as String?,
      );
      final medal = ['🥇', '🥈', '🥉'][place];
      final heights = [92.h, 72.h, 60.h];
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            DecoratedAvatar(
              avatarUrl: user['avatar_url'] as String?,
              radius: (place == 0 ? 34 : 26).r,
              frameGradient: ring,
            ),
            SizedBox(height: 6.h),
            Text(medal, style: TextStyle(fontSize: 16.sp)),
            SizedBox(
              width: 90.w,
              child: DecoratedUsername(
                profile: user,
                baseStyle: TextStyle(fontSize: 11.sp, color: Colors.white),
              ),
            ),
            Text('${e['score'] ?? 0} 💎',
                style: TextStyle(fontSize: 11.sp, color: Colors.amber)),
            SizedBox(height: 8.h),
            Container(
              height: heights[place],
              decoration: BoxDecoration(
                color: place == 0 ? Colors.amber.shade700 : place == 1 ? Colors.blueGrey : Colors.brown,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
              ),
              alignment: Alignment.center,
              child: Text('TOP ${place + 1}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [podiumSlot(top3, 0), podiumSlot(top3, 1), podiumSlot(top3, 2)],
      ),
    );
  }

  Widget _buildTile(dynamic entry, int index) {
    final user = entry['user'] as Map<String, dynamic>? ?? {};
    final rank = entry['rank'] ?? index + 1;
    return ListTile(
      leading: CircleAvatar(
        radius: 18.r,
        backgroundColor: Theme.of(context).cardColor,
        child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp)),
      ),
      title: Row(
        children: [
          CachedNetworkImage(
            imageUrl: (user['avatar_url'] as String?)?.isNotEmpty == true
                ? user['avatar_url'] as String
                : 'https://via.placeholder.com/50',
            width: 28.r,
            height: 28.r,
            imageBuilder: (_, image) => CircleAvatar(backgroundImage: image, radius: 14.r),
            errorWidget: (_, __, ___) => const CircleAvatar(child: Icon(Icons.person)),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: DecoratedUsername(profile: user, baseStyle: TextStyle(fontSize: 13.sp)),
          ),
        ],
      ),
      trailing: Text('${entry['score'] ?? 0}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
    );
  }
}
