import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/agora_service.dart';
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import '../../utils/api_error.dart';

class GroupCallRoomScreen extends StatefulWidget {
  const GroupCallRoomScreen({super.key});

  @override
  State<GroupCallRoomScreen> createState() => _GroupCallRoomScreenState();
}

class _GroupCallRoomScreenState extends State<GroupCallRoomScreen> {
  String _roomId = '';
  Map<String, dynamic>? _room;
  List<Map<String, dynamic>> _seats = [];
  bool _isLoading = true;
  bool _isJoined = false;
  String? _error;

  int _localUid = 0;
  int? _remoteUid;
  final Set<int> _remoteUids = {};

  bool _isMuted = false;
  bool _isVideoOff = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && _roomId.isEmpty) {
      _roomId = args['roomId'] as String? ?? '';
      if (_roomId.isNotEmpty) _loadRoom();
    }
  }

  @override
  void dispose() {
    _leaveAndCleanup();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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

  Future<void> _loadRoom() async {
    try {
      final res = await ApiService.get('/group-calls/$_roomId');
      if (!mounted) return;
      final data = res.data['data'] as Map<String, dynamic>;
      setState(() {
        _room = data;
        _seats = (data['seats'] as List<dynamic>?)
                ?.map((s) => Map<String, dynamic>.from(s))
                .toList() ?? [];
        _isLoading = false;
      });
      _connectAgora();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _isLoading = false; });
    }
  }

  void _registerAgoraHandlers() {
    AgoraService.engine?.registerEventHandler(
      RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() {
            _remoteUids.add(remoteUid);
            _remoteUid ??= remoteUid;
          });
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted) setState(() {
            _remoteUids.remove(remoteUid);
            if (_remoteUid == remoteUid) {
              _remoteUid = _remoteUids.isNotEmpty ? _remoteUids.first : null;
            }
          });
        },
      ),
    );
  }

  void _registerSocketHandlers() {
    SocketService.onGroupCallMessage((data) {
      if (mounted && data is Map) {
        // Could show in a mini-chat overlay
      }
    });

    SocketService.onGroupCallSeatUpdate((data) {
      if (mounted && data is Map) {
        _loadRoom();
      }
    });

    SocketService.onGroupCallGift((data) {
      if (mounted && data is Map) {
        // Could show gift animation overlay
      }
    });
  }

  Future<void> _connectAgora() async {
    try {
      await AgoraService.initialize();
      await AgoraService.requestPermissions();

      final tokenRes = await ApiService.get('/group-calls/$_roomId/token');
      final tokenData = tokenRes.data['data'];
      final token = tokenData['token'] as String;
      final channelName = tokenData['channel_name'] as String;
      _localUid = tokenData['uid'] as int? ?? _uidFromUser();
      final isPublisher = tokenData['role'] == 'publisher';

      _registerAgoraHandlers();

      await AgoraService.joinChannel(
        channelName,
        token,
        _localUid,
        isPublisher,
      );

      await SocketService.connect();
      SocketService.joinGroupCall(_roomId);
      _registerSocketHandlers();

      setState(() => _isJoined = true);
    } catch (e) {
      if (mounted) {
        final message = e is AgoraConfigurationException
            ? e.message
            : 'Failed to join: ${friendlyError(e)}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _leaveAndCleanup() async {
    SocketService.leaveGroupCall(_roomId);
    try {
      await ApiService.post('/group-calls/$_roomId/leave');
    } catch (_) {}
    await AgoraService.leaveChannel();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    try {
      setState(() => _isMuted = !_isMuted);
      await AgoraService.engine!.muteLocalAudioStream(_isMuted);
      final mySeat = _seats.firstWhere(
        (s) => s['user_id'] == Supabase.instance.client.auth.currentUser?.id,
        orElse: () => <String, dynamic>{},
      );
      if (mySeat.isNotEmpty) {
        mySeat['is_muted'] = _isMuted;
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _toggleVideo() async {
    try {
      setState(() => _isVideoOff = !_isVideoOff);
      await AgoraService.engine!.muteLocalVideoStream(_isVideoOff);
      final mySeat = _seats.firstWhere(
        (s) => s['user_id'] == Supabase.instance.client.auth.currentUser?.id,
        orElse: () => <String, dynamic>{},
      );
      if (mySeat.isNotEmpty) {
        mySeat['video_enabled'] = !_isVideoOff;
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _kickUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kick user?'),
        content: const Text('Remove this person from the call?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kick', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.post('/group-calls/$_roomId/kick/$userId');
      _loadRoom();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _endCall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End group call?'),
        content: const Text('This will end the call for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.post('/group-calls/$_roomId/end');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 14.sp)),
              SizedBox(height: 12.h),
              FilledButton(onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back')),
            ],
          ),
        )),
      );
    }

    final isHost = _room?['host_id'] == Supabase.instance.client.auth.currentUser?.id;
    final maxSeats = (_room?['max_seats'] as int?) ?? 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isHost),
            Expanded(child: _buildVideoGrid(maxSeats)),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isHost) {
    final host = _room?['profiles'] as Map<String, dynamic>? ?? {};
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.close, color: Colors.white, size: 24.r),
          ),
          SizedBox(width: 8.w),
          CircleAvatar(
            radius: 14.r,
            backgroundImage: host['avatar_url'] != null
                ? CachedNetworkImageProvider(host['avatar_url'] as String)
                : null,
            child: host['avatar_url'] == null ? Icon(Icons.person, size: 14.r) : null,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(_room?['title'] ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    if (host['is_verified'] == true) ...[
                      SizedBox(width: 4.w),
                      Icon(Icons.verified, size: 12.r, color: Colors.blue),
                    ],
                  ],
                ),
                Text(_room?['category'] ?? 'general',
                    style: TextStyle(fontSize: 10.sp, color: Colors.white54)),
              ],
            ),
          ),
          if (isHost)
            IconButton(
              icon: Icon(Icons.stop_circle, color: Colors.red, size: 28.r),
              tooltip: 'End call',
              onPressed: _endCall,
            ),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(int maxSeats) {
    final occupiedSeats = _seats.where((s) => s['user_id'] != null).toList();
    final cols = maxSeats <= 4 ? 2 : maxSeats <= 9 ? 3 : 4;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 4.w,
          crossAxisSpacing: 4.w,
          childAspectRatio: 0.75,
        ),
        itemCount: maxSeats,
        itemBuilder: (context, index) {
          final seat = occupiedSeats.where((s) => s['seat_index'] == index).firstOrNull;
          return _buildSeatTile(index, seat);
        },
      ),
    );
  }

  Widget _buildSeatTile(int index, Map<String, dynamic>? seat) {
    final isHostSeat = seat?['role'] == 'host';
    final isCoHost = seat?['role'] == 'co_host';
    final profile = seat?['profiles'] as Map<String, dynamic>? ?? {};
    final userId = seat?['user_id'] as String?;
    final isMe = userId == Supabase.instance.client.auth.currentUser?.id;

    if (seat == null || userId == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: Colors.grey.shade800, width: 1),
        ),
        child: Center(
          child: Icon(Icons.add_circle_outline, color: Colors.grey.shade600, size: 28.r),
        ),
      );
    }

    return GestureDetector(
      onLongPress: () {
        final isHost = _room?['host_id'] == Supabase.instance.client.auth.currentUser?.id;
        if (!isMe && (isHost || isCoHost)) {
          _showSeatActions(seat);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isHostSeat ? Colors.amber : isCoHost ? Colors.blue : Colors.transparent,
            width: isHostSeat || isCoHost ? 2 : 0,
          ),
        ),
        child: Stack(
          children: [
            if (isMe && _isJoined)
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: AgoraService.engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              )
            else if (!isMe)
              Center(
                child: profile['avatar_url'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: CachedNetworkImage(
                          imageUrl: profile['avatar_url'] as String,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      )
                    : CircleAvatar(
                        radius: 28.r,
                        backgroundColor: Colors.grey.shade800,
                        child: Text(
                          (profile['display_name'] ?? profile['username'] ?? '?')[0].toUpperCase(),
                          style: TextStyle(fontSize: 20.sp, color: Colors.white),
                        ),
                      ),
              )
            else
              Center(
                child: profile['avatar_url'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: CachedNetworkImage(
                          imageUrl: profile['avatar_url'] as String,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      )
                    : CircleAvatar(
                        radius: 28.r,
                        backgroundColor: Colors.grey.shade800,
                        child: Text(
                          (profile['display_name'] ?? profile['username'] ?? '?')[0].toUpperCase(),
                          style: TextStyle(fontSize: 20.sp, color: Colors.white),
                        ),
                      ),
              ),
            if (seat['is_muted'] == true)
              Positioned(
                top: 4.w, right: 4.w,
                child: Container(
                  padding: EdgeInsets.all(2.w),
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha(200),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_off, size: 12.r, color: Colors.white),
                ),
              ),
            if (seat['video_enabled'] == false)
              Positioned(
                top: 4.w, left: 4.w,
                child: Container(
                  padding: EdgeInsets.all(2.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(200),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.videocam_off, size: 12.r, color: Colors.white),
                ),
              ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(180)],
                  ),
                ),
                child: Row(
                  children: [
                    if (isHostSeat)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                        margin: EdgeInsets.only(right: 4.w),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text('HOST', style: TextStyle(fontSize: 7.sp, fontWeight: FontWeight.bold)),
                      ),
                    if (isCoHost)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                        margin: EdgeInsets.only(right: 4.w),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text('MOD', style: TextStyle(fontSize: 7.sp, fontWeight: FontWeight.bold)),
                      ),
                    Flexible(
                      child: Text(profile['display_name'] ?? profile['username'] ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.sp, color: Colors.white)),
                    ),
                    if (profile['is_verified'] == true)
                      Icon(Icons.verified, size: 10.r, color: Colors.blue),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeatActions(Map<String, dynamic> seat) {
    final profile = seat['profiles'] as Map<String, dynamic>? ?? {};
    final isMe = seat['user_id'] == Supabase.instance.client.auth.currentUser?.id;
    final isHost = _room?['host_id'] == Supabase.instance.client.auth.currentUser?.id;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: profile['avatar_url'] != null
                    ? CachedNetworkImageProvider(profile['avatar_url'] as String)
                    : null,
              ),
              title: Text(profile['display_name'] ?? profile['username'] ?? 'User'),
              subtitle: Text(seat['role'] ?? 'guest'),
            ),
            if (isHost && !isMe) ...[
              ListTile(
                leading: Icon(seat['role'] == 'co_host' ? Icons.star_outline : Icons.star),
                title: Text(seat['role'] == 'co_host' ? 'Revoke moderator' : 'Grant moderator'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiService.post(
                      '/group-calls/$_roomId/grant-co-host/${seat['user_id']}',
                      data: {'grant': seat['role'] != 'co_host'},
                    );
                    _loadRoom();
                  } catch (e) {
                    if (mounted) showApiError(context, e);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove, color: Colors.red),
                title: const Text('Kick', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(ctx); _kickUser(seat['user_id']); },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildControlButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            label: _isMuted ? 'Unmute' : 'Mute',
            onTap: _toggleMute,
          ),
          _buildControlButton(
            icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
            label: _isVideoOff ? 'Camera off' : 'Camera on',
            onTap: _toggleVideo,
          ),
          _buildControlButton(
            icon: Icons.card_giftcard,
            label: 'Gift',
            onTap: _showGiftPicker,
          ),
          _buildControlButton(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            onTap: _showChatSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48.r, height: 48.r,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22.r),
          ),
          SizedBox(height: 4.h),
          Text(label, style: TextStyle(fontSize: 9.sp, color: Colors.white70)),
        ],
      ),
    );
  }

  void _showGiftPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => Container(
          padding: EdgeInsets.all(16.w),
          child: Column(
            children: [
              Container(
                width: 40.w, height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 12.h),
              Text('Send a Gift', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 12.h),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  controller: scrollController,
                  mainAxisSpacing: 8.w,
                  crossAxisSpacing: 8.w,
                  children: [
                    _buildGiftItem('🌹', 'Rose', 10),
                    _buildGiftItem('💎', 'Diamond', 50),
                    _buildGiftItem('🎵', 'Song', 100),
                    _buildGiftItem('🎁', 'Gift Box', 200),
                    _buildGiftItem('🔥', 'Fire', 500),
                    _buildGiftItem('👑', 'Crown', 1000),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGiftItem(String emoji, String name, int cost) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        SocketService.sendGroupCallGift(_roomId, name.toLowerCase(), 1);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56.r, height: 56.r,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Center(child: Text(emoji, style: TextStyle(fontSize: 28.r))),
          ),
          SizedBox(height: 2.h),
          Text(name, style: TextStyle(fontSize: 9.sp, color: Colors.white70)),
          Text('$cost 💎', style: TextStyle(fontSize: 8.sp, color: Colors.amber)),
        ],
      ),
    );
  }

  void _showChatSheet() {
    final messages = <Map<String, dynamic>>[];
    final inputController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          SocketService.onGroupCallMessage((data) {
            setModalState(() => messages.add(Map<String, dynamic>.from(data)));
          });

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(ctx).size.height * 0.5,
              padding: EdgeInsets.all(12.w),
              child: Column(
                children: [
                  Container(
                    width: 40.w, height: 4.h,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text('Group Chat', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8.h),
                  Expanded(
                    child: ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) {
                        final msg = messages[i];
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 2.h),
                          child: Text(
                            '${msg['username'] ?? 'User'}: ${msg['message'] ?? ''}',
                            style: TextStyle(fontSize: 12.sp),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputController,
                          decoration: const InputDecoration(hintText: 'Type a message...'),
                          onSubmitted: (text) {
                            if (text.trim().isNotEmpty) {
                              SocketService.sendGroupCallMessage(_roomId, text.trim());
                              inputController.clear();
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          final text = inputController.text.trim();
                          if (text.isNotEmpty) {
                            SocketService.sendGroupCallMessage(_roomId, text);
                            inputController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
