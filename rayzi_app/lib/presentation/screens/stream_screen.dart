import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/agora_service.dart';
import '../../services/socket_service.dart';
import '../../services/api_service.dart';

class StreamScreen extends StatefulWidget {
  final Map<String, dynamic> stream;
  const StreamScreen({super.key, required this.stream});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _isLoading = true;
  String? _token;
  String? _channelName;
  bool _isHost = false;
  int _uid = 0;
  int? _remoteUid;
  final _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  /// Agora requires a numeric UID unique **per participant** — deriving it
  /// from our own user id guarantees viewers never collide with each other
  /// or with the host (the previous host-id-derived approach kicked every
  /// duplicate viewer out of the channel).
  int _uidFromUser() {
    final id = Supabase.instance.client.auth.currentUser?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    var hash = 0;
    for (final code in id.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return hash;
  }

  void _registerAgoraHandlers() {
    AgoraService.engine?.registerEventHandler(
      RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted && _remoteUid == remoteUid) setState(() => _remoteUid = null);
        },
      ),
    );
  }

  Future<void> _initializeStream() async {
    try {
      await AgoraService.initialize();
      await AgoraService.requestPermissions();

      final tokenArgs = <String, dynamic>{};
      final argsPassword = widget.stream['password'];
      if (argsPassword is String && argsPassword.isNotEmpty) {
        tokenArgs['password'] = argsPassword;
      }
      final response = await ApiService.get(
        '/streams/${widget.stream['id']}/token',
        queryParameters: tokenArgs.isEmpty ? null : tokenArgs,
      );
      // The RTC token is bound to a server-derived uid — always use the
      // uid returned by the backend, never a client-side derivation.
      _token = response.data['data']['token'];
      _isHost = response.data['data']['is_host'];
      _uid = response.data['data']['uid'] as int? ?? _uidFromUser();
      _channelName =
          response.data['data']['channel_name'] as String? ?? widget.stream['channel_name'];

      _registerAgoraHandlers();

      await AgoraService.joinChannel(
        _channelName!,
        _token!,
        _uid,
        _isHost,
      );

      await SocketService.connect();
      SocketService.joinStream(widget.stream['id']);

      SocketService.onChatMessage((data) {
        if (mounted && data is Map) {
          setState(() => _messages.add(Map<String, dynamic>.from(data)));
        }
      });

      await ApiService.post('/streams/${widget.stream['id']}/join');

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join stream: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    SocketService.offChatMessage();
    SocketService.leaveStream(widget.stream['id']);
    ApiService.post('/streams/${widget.stream['id']}/leave').then<void>((_) {}, onError: (Object _) {});
    AgoraService.leaveChannel();
    _chatController.dispose();
    super.dispose();
  }

  Widget _buildVideoArea() {
    final engine = AgoraService.engine!;
    // Host always renders its own camera; audience renders the broadcaster's feed.
    if (_isHost) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: 0),
        ),
      );
    }
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: _remoteUid),
        ),
      );
    }
    return const Center(child: Text('Waiting for the host…', style: TextStyle(color: Colors.white70)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              // Video view
              _buildVideoArea(),
              // Chat overlay
              Positioned(
                bottom: 80.h,
                left: 16.w,
                right: 16.w,
                child: Container(
                  height: 200.h,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[_messages.length - 1 - index];
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                        child: Text(
                          '${msg['username']}: ${msg['message']}',
                          style: TextStyle(color: Colors.white, fontSize: 12.sp),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Chat input
              Positioned(
                bottom: 16.h,
                left: 16.w,
                right: 16.w,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.black54,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.r)),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {
                        if (_chatController.text.isNotEmpty) {
                          SocketService.sendChatMessage(widget.stream['id'], _chatController.text);
                          _chatController.clear();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.card_giftcard, color: Colors.amber),
                      onPressed: () => _showGiftSheet(),
                    ),
                  ],
                ),
              ),
              // Viewer count
              Positioned(
                top: 40.h,
                left: 16.w,
                child: Text('${widget.stream['current_viewers'] ?? 0} watching',
                  style: const TextStyle(color: Colors.white)),
              ),
              // Close button
              Positioned(
                top: 40.h,
                right: 16.w,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    if (_isHost) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('End Stream?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () {
                                ApiService.post('/streams/${widget.stream['id']}/end').then<void>((_) {}, onError: (Object _) {});
                                Navigator.pop(ctx);
                                Navigator.pop(context);
                              },
                              child: const Text('End'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ),
    );
  }

  void _showGiftSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Container(
        height: 300.h,
        padding: EdgeInsets.all(16.w),
        child: Column(
          children: [
            Text('Send Gift', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
            SizedBox(height: 16.h),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                childAspectRatio: 0.8,
                children: List.generate(6, (index) {
                  final gifts = ['Rose', 'Heart', 'Teddy', 'Crown', 'Car', 'Yacht'];
                  final prices = [10, 50, 100, 500, 1000, 5000];
                  return GestureDetector(
                    onTap: () async {
                      try {
                        await ApiService.post('/gifts/send', data: {
                          'stream_id': widget.stream['id'],
                          'gift_id': 'gift_$index',
                          'receiver_id': widget.stream['host_id'],
                          'quantity': 1,
                        });
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gift failed: $e')),
                          );
                        }
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.card_giftcard, size: 40.w, color: Colors.amber),
                        Text(gifts[index], style: TextStyle(fontSize: 12.sp)),
                        Text('${prices[index]} coins',
                          style: TextStyle(fontSize: 10.sp, color: Colors.grey)),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
