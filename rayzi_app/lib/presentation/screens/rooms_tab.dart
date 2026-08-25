import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';

class RoomsTab extends StatefulWidget {
  const RoomsTab({super.key});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  List<dynamic> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      final response = await ApiService.get('/rooms');
      setState(() {
        _rooms = response.data['data'] ?? [];
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
      appBar: AppBar(title: const Text('Audio Rooms')),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadRooms,
            child: _rooms.isEmpty
              ? ListView(children: const [SizedBox(height: 200), Center(child: Text('No active rooms'))])
              : ListView.builder(
                  padding: EdgeInsets.all(12.w),
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final room = _rooms[index];
                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: CachedNetworkImageProvider(
                            room['profiles']?['avatar_url'] ?? 'https://via.placeholder.com/100',
                          ),
                        ),
                        title: Text(room['title'] ?? 'Untitled Room',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(room['profiles']?['display_name'] ?? 'Unknown',
                          style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha((0.2 * 255).round()),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text('ACTIVE',
                            style: TextStyle(color: Colors.green, fontSize: 10.sp)),
                        ),
                        onTap: () {
                          final roomId = room['id'] as String?;
                          if (roomId != null) {
                            Navigator.pushNamed(context, AppRoutes.room, arguments: {'roomId': roomId});
                          }
                        },
                      ),
                    );
                  },
                ),
          ),
    );
  }
}
