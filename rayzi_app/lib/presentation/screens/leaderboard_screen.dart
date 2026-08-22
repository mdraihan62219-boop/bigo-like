import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> _entries = [];
  String _period = 'daily';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/users/leaderboard',
        queryParameters: {'period': _period, 'category': 'streamer'});
      setState(() {
        _entries = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          DropdownButton<String>(
            value: _period,
            underline: const SizedBox(),
            items: ['daily', 'weekly', 'monthly']
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
            onChanged: (v) {
              setState(() => _period = v ?? 'daily');
              _load();
            },
          ),
          SizedBox(width: 16.w),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _entries.isEmpty
          ? const Center(child: Text('No leaderboard data'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final profile = entry['profiles'] ?? {};
                final medal = index == 0 ? '🥇' : index == 1 ? '🥈' : index == 2 ? '🥉' : '${index + 1}';
                return ListTile(
                  leading: Text(medal, style: TextStyle(fontSize: 18.sp)),
                  title: Row(
                    children: [
                      CircleAvatar(
                        radius: 16.r,
                        backgroundImage: CachedNetworkImageProvider(
                          profile['avatar_url'] ?? 'https://via.placeholder.com/50',
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(child: Text(profile['display_name'] ?? 'Unknown')),
                    ],
                  ),
                  trailing: Text('${entry['score'] ?? 0}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                );
              },
            ),
    );
  }
}
