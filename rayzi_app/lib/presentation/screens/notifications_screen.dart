import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiService.get('/notifications');
      setState(() {
        _notifications = response.data['data'] ?? [];
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

  IconData _iconFor(String type) {
    switch (type) {
      case 'follow': return Icons.person_add;
      case 'like': return Icons.favorite;
      case 'comment': return Icons.comment;
      case 'gift': return Icons.card_giftcard;
      case 'stream_start': return Icons.live_tv;
      default: return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await ApiService.post('/notifications/read-all');
              _load();
            },
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _notifications.isEmpty
          ? const Center(child: Text('No notifications'))
          : ListView.builder(
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final n = _notifications[index];
                return ListTile(
                  leading: Icon(_iconFor(n['type'] ?? '')),
                  title: Text(n['title'] ?? ''),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text(
                        DateFormat('MMM d, HH:mm').format(DateTime.parse(n['created_at'])),
                        style: TextStyle(fontSize: 11.sp, color: Colors.grey),
                      ),
                    ],
                  ),
                  tileColor: n['is_read'] == true ? null : Theme.of(context).primaryColor.withOpacity(0.1),
                  onTap: () async {
                    await ApiService.post('/notifications/${n['id']}/read');
                    _load();
                  },
                );
              },
            ),
    );
  }
}
