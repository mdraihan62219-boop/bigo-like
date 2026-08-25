import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';

class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key});

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class _BlockListScreenState extends State<BlockListScreen> {
  List<dynamic> _blocked = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.get('/users/blocked');
      setState(() {
        _blocked = res.data['data'] is List ? res.data['data'] : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Failed to load block list: $e'; _loading = false; });
    }
  }

  Future<void> _unblock(String userId) async {
    try {
      await ApiService.post('/users/$userId/unblock');
      setState(() => _blocked.removeWhere((u) => u['id'] == userId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unblock: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Block List')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _blocked.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, size: 64.r, color: Colors.grey[400]),
                          SizedBox(height: 12.h),
                          Text('No blocked users', style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _blocked.length,
                        itemBuilder: (context, index) {
                          final user = _blocked[index] as Map<String, dynamic>;
                          final avatar = user['avatar_url'] as String? ?? '';
                          final name = user['display_name'] ?? user['username'] ?? 'User';
                          return Card(
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 20.r,
                                backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                                child: avatar.isEmpty ? Icon(Icons.person, size: 20.r) : null,
                              ),
                              title: Text(name.toString(), style: TextStyle(fontSize: 14.sp)),
                              trailing: TextButton(
                                onPressed: () => _unblock(user['id']),
                                child: const Text('Unblock', style: TextStyle(color: Colors.red)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
