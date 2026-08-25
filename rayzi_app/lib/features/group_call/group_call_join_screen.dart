import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class GroupCallJoinScreen extends StatefulWidget {
  const GroupCallJoinScreen({super.key});

  @override
  State<GroupCallJoinScreen> createState() => _GroupCallJoinScreenState();
}

class _GroupCallJoinScreenState extends State<GroupCallJoinScreen> {
  List<dynamic> _rooms = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await ApiService.get('/group-calls');
      if (!mounted) return;
      setState(() {
        _rooms = res.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Video Calls'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Start group call',
            onPressed: () => Navigator.pushNamed(context, '/create-group-call'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red, fontSize: 14.sp)),
                      SizedBox(height: 12.h),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rooms.isEmpty
                      ? ListView(children: [
                          SizedBox(height: 120.h),
                          Icon(Icons.video_call_outlined, size: 64.r, color: Colors.grey),
                          SizedBox(height: 12.h),
                          Center(child: Text('No active group calls',
                              style: TextStyle(fontSize: 14.sp, color: Colors.grey))),
                          SizedBox(height: 8.h),
                          Center(child: Text('Start one or wait for others',
                              style: TextStyle(fontSize: 12.sp, color: Colors.grey))),
                        ])
                      : ListView.builder(
                          padding: EdgeInsets.all(12.w),
                          itemCount: _rooms.length,
                          itemBuilder: (context, index) {
                            final room = _rooms[index] as Map<String, dynamic>;
                            final host = room['profiles'] as Map<String, dynamic>? ?? {};
                            final seats = (room['seats'] as List<dynamic>?) ?? [];
                            return Card(
                              margin: EdgeInsets.only(bottom: 12.h),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 22.r,
                                  backgroundImage: host['avatar_url'] != null
                                      ? CachedNetworkImageProvider(host['avatar_url'] as String)
                                      : null,
                                  child: host['avatar_url'] == null ? const Icon(Icons.person) : null,
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(room['title'] ?? 'Group Call',
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                                    ),
                                    if (host['is_verified'] == true) ...[
                                      SizedBox(width: 4.w),
                                      Icon(Icons.verified, size: 14.r, color: Colors.blue),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '${host['display_name'] ?? host['username'] ?? 'Host'} · ${seats.where((s) => s['user_id'] != null).length}/${room['max_seats'] ?? 9} seats',
                                  style: TextStyle(fontSize: 11.sp, color: Colors.grey),
                                ),
                                trailing: FilledButton.tonal(
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/group-call-room',
                                        arguments: {'roomId': room['id']});
                                  },
                                  child: const Text('Join'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
