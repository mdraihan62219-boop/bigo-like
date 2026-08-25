import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/agora_service.dart';
import '../../services/socket_service.dart';
import '../../services/api_service.dart';
import '../../config/constants.dart';
import '../../features/pk/pk_screens.dart';

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
  bool _cameraEnabled = true;
  bool _isMuted = false;
  int _viewerCount = 0;
  String _broadcasterName = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

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

  void _registerSocketHandlers() {
    SocketService.onChatMessage((data) {
      if (mounted && data is Map) {
        setState(() => _messages.add({
          'type': 'chat',
          'username': data['username'] ?? 'User',
          'message': data['message'] ?? '',
        }));
      }
    });

    SocketService.onGiftReceived((data) {
      if (mounted && data is Map) {
        setState(() => _messages.add({
          'type': 'gift',
          'username': data['sender_name'] ?? 'Someone',
          'message': 'sent a ${data['gift_name'] ?? 'gift'}',
        }));
      }
    });

    SocketService.onUserJoined((data) {
      if (mounted && data is Map) {
        final name = data['username'] ?? data['display_name'] ?? 'Someone';
        setState(() {
          _messages.add({'type': 'join', 'message': '$name joined'});
          _viewerCount = (_viewerCount) + 1;
        });
      }
    });

    SocketService.onUserLeft((data) {
      if (mounted) {
        setState(() {
          if (_viewerCount > 0) _viewerCount--;
        });
      }
    });

    // PK match found — navigate to battle view.
    SocketService.onPkMatched((data) {
      if (mounted && data is Map && data['battleId'] != null) {
        Navigator.pushNamed(context, '/pk-battle', arguments: {'id': data['battleId']});
      }
    });
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
      _token = response.data['data']['token'];
      _isHost = response.data['data']['is_host'];
      _uid = response.data['data']['uid'] as int? ?? _uidFromUser();
      _channelName =
          response.data['data']['channel_name'] as String? ?? widget.stream['channel_name'];

      _broadcasterName = widget.stream['profiles']?['display_name'] ??
          widget.stream['profiles']?['username'] ??
          widget.stream['host_id'] ?? 'Host';

      _registerAgoraHandlers();

      await AgoraService.joinChannel(
        _channelName!,
        _token!,
        _uid,
        _isHost,
      );

      await SocketService.connect();
      SocketService.joinStream(widget.stream['id']);
      _registerSocketHandlers();

      await ApiService.post('/streams/${widget.stream['id']}/join');

      _viewerCount = widget.stream['current_viewers'] ?? 0;

      // Poll viewer count every 15 seconds.
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        try {
          final res = await ApiService.get('/streams/${widget.stream['id']}');
          if (mounted) {
            final data = res.data['data'];
            setState(() => _viewerCount = data?['current_viewers'] ?? _viewerCount);
          }
        } catch (_) {}
      });

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        String message;
        if (e is AgoraConfigurationException) {
          message = e.message;
        } else if (e is DioException && e.response?.statusCode == 503) {
          message = 'Live streaming is not configured yet — please check back soon';
        } else {
          message = 'Failed to join stream: $e';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SocketService.offChatMessage();
    SocketService.offGiftReceived();
    SocketService.offUserJoined();
    SocketService.offUserLeft();
    SocketService.offPkScoreUpdate();
    SocketService.offPkMatched();
    SocketService.leaveStream(widget.stream['id']);
    ApiService.post('/streams/${widget.stream['id']}/leave').then<void>((_) {}, onError: (Object _) {});
    AgoraService.leaveChannel();
    _chatController.dispose();
    super.dispose();
  }

  Widget _buildVideoArea() {
    final engine = AgoraService.engine!;
    if (_isHost) {
      return AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
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

  void _toggleCamera() async {
    try {
      await AgoraService.engine!.enableVideo();
      setState(() => _cameraEnabled = !_cameraEnabled);
      await AgoraService.engine!.muteLocalVideoStream(!_cameraEnabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera toggle failed: $e')),
        );
      }
    }
  }

  void _toggleMute() async {
    try {
      setState(() => _isMuted = !_isMuted);
      await AgoraService.engine!.muteLocalAudioStream(_isMuted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mute toggle failed: $e')),
        );
      }
    }
  }

  void _shareStream() async {
    final streamUrl = '${AppConstants.apiBaseUrl.replaceFirst('/api/v1', '')}/stream/${widget.stream['id']}';
    try {
      await Share.share(
        'Check out this live stream on PHM Live!\n$streamUrl',
        subject: 'Live Stream on PHM Live',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  void _sendReaction() async {
    try {
      await ApiService.post('/streams/${widget.stream['id']}/like');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❤️'),
            duration: Duration(milliseconds: 500),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : Stack(
            children: [
              _buildVideoArea(),

              // Top bar: viewer count, broadcaster name, close.
              Positioned(
                top: 44.h,
                left: 16.w,
                right: 16.w,
                child: Row(
                  children: [
                    // Viewer count pill.
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility, color: Colors.white70, size: 14),
                          SizedBox(width: 4.w),
                          Text('$_viewerCount', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    // Broadcaster name in description area.
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Text(
                          _broadcasterName,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // Close button.
                    IconButton(
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
                  ],
                ),
              ),

              // Right-side control buttons (host only).
              if (_isHost)
                Positioned(
                  right: 12.w,
                  top: 120.h,
                  child: Column(
                    children: [
                      _controlButton(
                        icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                        label: 'Camera',
                        onTap: _toggleCamera,
                      ),
                      SizedBox(height: 12.h),
                      _controlButton(
                        icon: _isMuted ? Icons.mic_off : Icons.mic,
                        label: 'Mute',
                        onTap: _toggleMute,
                      ),
                      SizedBox(height: 12.h),
                      // PK Battle queue button.
                      PkQueueButton(streamId: widget.stream['id']),
                    ],
                  ),
                ),

              // Reaction button (bottom-right).
              Positioned(
                right: 16.w,
                bottom: 100.h,
                child: GestureDetector(
                  onTap: _sendReaction,
                  child: Container(
                    width: 50.r,
                    height: 50.r,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite, color: Colors.red, size: 28),
                  ),
                ),
              ),

              // Share button (bottom-right, above reactions).
              Positioned(
                right: 16.w,
                bottom: 160.h,
                child: GestureDetector(
                  onTap: _shareStream,
                  child: Container(
                    width: 50.r,
                    height: 50.r,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share, color: Colors.white, size: 22),
                  ),
                ),
              ),

              // Chat feed area.
              Positioned(
                bottom: 80.h,
                left: 16.w,
                right: 80.w,
                child: Container(
                  height: 200.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha((0.3 * 255).round()),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    padding: EdgeInsets.all(8.w),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[_messages.length - 1 - index];
                      return _buildChatItem(msg);
                    },
                  ),
                ),
              ),

              // Chat input bar.
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () {
                        if (_chatController.text.isNotEmpty) {
                          SocketService.sendChatMessage(widget.stream['id'], _chatController.text);
                          setState(() => _messages.add({
                            'type': 'chat',
                            'username': 'You',
                            'message': _chatController.text,
                          }));
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
            ],
          ),
    );
  }

  Widget _buildChatItem(Map<String, dynamic> msg) {
    final type = msg['type'] ?? 'chat';
    switch (type) {
      case 'join':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 2.h),
          child: Text(
            msg['message'] ?? '',
            style: TextStyle(color: Colors.white54, fontSize: 11.sp, fontStyle: FontStyle.italic),
          ),
        );
      case 'gift':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 2.h),
          child: Text(
            '🎁 ${msg['username']} ${msg['message']}',
            style: TextStyle(color: Colors.amber, fontSize: 11.sp, fontWeight: FontWeight.w600),
          ),
        );
      default:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 2.h),
          child: RichText(
            text: TextSpan(
              text: '${msg['username']}: ',
              style: TextStyle(color: Colors.lightBlueAccent, fontSize: 12.sp, fontWeight: FontWeight.w600),
              children: [
                TextSpan(
                  text: msg['message'] ?? '',
                  style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _controlButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48.r,
        height: 48.r,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
                        SocketService.sendGift(widget.stream['id'], 'gift_$index', widget.stream['host_id']);
                        setState(() => _messages.add({
                          'type': 'gift',
                          'username': 'You',
                          'message': 'sent a ${gifts[index]}',
                        }));
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
