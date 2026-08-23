import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';
import '../../features/shared/decorated_widgets.dart';

/// Opens the leaderboard the way the reference app does — as a rounded
/// modal sheet with a close button, not a pushed full-screen page.
Future<void> showLeaderboardSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.94,
      maxChildSize: 0.97,
      minChildSize: 0.6,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18.r)),
        ),
        child: LeaderboardSheet(listController: scrollController),
      ),
    ),
  );
}

/// Full-screen fallback (route target); Profile opens [showLeaderboardSheet].
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.maybePop(context)),
        ],
      ),
      body: const LeaderboardSheet(),
    );
  }
}

class LeaderboardSheet extends StatefulWidget {
  const LeaderboardSheet({super.key, this.listController});
  final ScrollController? listController;

  @override
  State<LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<LeaderboardSheet>
    with SingleTickerProviderStateMixin {
  List<dynamic> _entries = [];
  String _type = 'gifters'; // gifters | hosts
  bool _rewardable = false;
  String _period = 'daily';
  bool _isLoading = true;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  static const _periods = ['daily', 'weekly', 'monthly', 'all'];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {
          _type = _tabs.index < 2 ? 'gifters' : 'hosts';
          _rewardable = _tabs.index == 1 || _tabs.index == 3;
        });
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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

  /// Trust/tier chip under each username, mirroring the reference layout
  /// ("Official Reseller" / "General User" style labels).
  String _tierLabel(Map<String, dynamic> user) {
    if (user['role'] == 'admin') return 'Admin';
    if (user['role'] == 'host' || user['role'] == 'Official Host') return 'Official Host';
    if (user['is_verified'] == true) return 'Verified';
    return 'General User';
  }

  @override
  Widget build(BuildContext context) {
    final top3 = _entries.take(3).toList();
    return Column(
      children: [
        // Grab handle + title row with X close button (reference layout).
        Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Container(
            width: 44.w, height: 4.h,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
        ),
        Row(
          children: [
            SizedBox(width: 16.w),
            Expanded(child: Text('Leaderboard',
                style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold))),
            IconButton(
              icon: Icon(Icons.close, size: 22.r),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        // Period filter
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: [
              for (final p in _periods)
                Padding(
                  padding: EdgeInsets.only(right: 8.w),
                  child: ChoiceChip(
                    label: Text(p, style: TextStyle(fontSize: 11.sp)),
                    selected: _period == p,
                    onSelected: (_) {
                      setState(() => _period = p);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 4.h),
        TabBar(
          controller: _tabs,
          labelStyle: TextStyle(fontSize: 11.sp),
          unselectedLabelColor: Colors.grey,
          labelColor: Theme.of(context).colorScheme.primary,
          indicatorColor: Theme.of(context).colorScheme.primary,
          isScrollable: false,
          tabs: const [
            Tab(text: 'Top Gifters'),
            Tab(text: 'Rewardable'),
            Tab(text: 'Top Hosts'),
            Tab(text: 'R. Hosts'),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _entries.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('No leaderboard data yet')),
                        ])
                      : ListView.builder(
                          controller: widget.listController,
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
      ],
    );
  }

  // DraggableScrollableSheet's controller is passed in via [listController].

  List<Widget> _buildRest() {
    return [for (int i = 3; i < _entries.length; i++) _buildTile(_entries[i], i)];
  }

  Widget _podiumSlot(List<dynamic> top3, int slot) {
    final place = [1, 0, 2][slot]; // visual order: 2nd | 1st | 3rd
    if (place >= top3.length) return const Expanded(child: SizedBox());
    final e = top3[place];
    final user = e['user'] as Map<String, dynamic>? ?? {};
    final ring = ProfileCosmetics.frameFor(
      (user['equipped_frame'] as Map<String, dynamic>?)?['tier'] as String?,
    );
    final heights = [86.h, 66.h, 54.h];
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            DecoratedAvatar(
              avatarUrl: user['avatar_url'] as String?,
              radius: (place == 0 ? 32 : 25).r,
              frameGradient: ring,
            ),
            Positioned(
              top: -10.h,
              child: CircleAvatar(
                radius: 11.r,
                backgroundColor: place == 0 ? Colors.amber : Colors.grey,
                child: Text('${place + 1}',
                    style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          SizedBox(height: 6.h),
          SizedBox(
            width: 96.w,
            child: DecoratedUsername(
              profile: user,
              baseStyle: TextStyle(fontSize: 11.sp, color: Colors.white),
            ),
          ),
          Text('${e['score'] ?? 0} 💎',
              style: TextStyle(fontSize: 11.sp, color: Colors.amber)),
          Container(
            margin: EdgeInsets.only(top: 3.h),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(_tierLabel(user),
                style: TextStyle(fontSize: 9.sp, color: Colors.white70)),
          ),
          SizedBox(height: 8.h),
          Container(
            height: heights[place],
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: 6.w),
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

  Widget _buildPodium(List<dynamic> top3) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _podiumSlot(top3, 0),
          _podiumSlot(top3, 1),
          _podiumSlot(top3, 2),
        ],
      ),
    );
  }

  Widget _buildTile(dynamic entry, int index) {
    final user = entry['user'] as Map<String, dynamic>? ?? {};
    final rank = entry['rank'] ?? index + 1;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16.r,
        backgroundColor: Theme.of(context).cardColor,
        child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp)),
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
          Expanded(child: DecoratedUsername(profile: user, baseStyle: TextStyle(fontSize: 13.sp))),
        ],
      ),
      subtitle: Text(_tierLabel(user), style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
      trailing: Text('${entry['score'] ?? 0} 💎',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.sp, color: Colors.amber)),
    );
  }
}
