import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import '../../services/agora_service.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class RoomDetailScreen extends StatefulWidget {
  final String roomId;
  const RoomDetailScreen({required this.roomId, super.key});

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  Map<String, dynamic>? _room;
  bool _isLoading = true;
  bool _isJoined = false;
  bool _joining = false;
  int? _remoteUid;
  String _connectionState = 'idle';

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  Future<void> _loadRoom() async {
    try {
      final response = await ApiService.get('/rooms/${widget.roomId}');
      if (!mounted) return;
      setState(() {
        _room = response.data['data'] ?? {};
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load room: ${friendlyError(e)}')));
    }
  }

  List<dynamic> get _participants =>
      (_room?['room_participants'] as List<dynamic>?) ?? [];

  void _registerAgoraHandlers() {
    AgoraService.engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('[AudioRoom] joinChannel success channel=${connection.channelId} uid=${connection.localUid}');
          if (mounted) setState(() => _connectionState = 'connected');
        },
        onLeaveChannel: (connection, stats) {
          debugPrint('[AudioRoom] left channel');
          if (mounted) {
            setState(() {
              _connectionState = 'left';
              _remoteUid = null;
            });
          }
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('[AudioRoom] user joined uid=$remoteUid');
          if (mounted) setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('[AudioRoom] user offline uid=$remoteUid');
          if (mounted && _remoteUid == remoteUid) {
            setState(() => _remoteUid = null);
          }
        },
        onError: (err, msg) {
          debugPrint('[AudioRoom] agora error code=$err msg=$msg');
        },
      ),
    );
  }

  Future<void> _joinRoom() async {
    if (_isJoined || _joining) return;
    setState(() => _joining = true);
    try {
      await AgoraService.initialize();
      await AgoraService.requestPermissions();

      // Same token service as Go Live / 1-to-1 calls — no second path.
      final response = await ApiService.get('/rooms/${widget.roomId}/token');
      final data = response.data['data'] as Map<String, dynamic>;
      final token = data['token'] as String;
      final channelName = data['channel_name'] as String;
      final uid = data['uid'] as int;
      final canPublish = data['role'] == 'speaker';

      _registerAgoraHandlers();
      await AgoraService.joinAudioChannel(channelName, token, uid, canPublish);

      // Register in the backend participant list (also enforces capacity).
      await ApiService.post('/rooms/${widget.roomId}/join');

      if (!mounted) return;
      setState(() {
        _isJoined = true;
        _joining = false;
      });
    } catch (e) {
      debugPrint('[AudioRoom] join failed: $e');
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join room: ${friendlyError(e)}')),
      );
    }
  }

  Future<void> _leaveRoom() async {
    if (!_isJoined) return;
    try {
      await ApiService.post('/rooms/${widget.roomId}/leave');
    } catch (_) {}
    await AgoraService.leaveChannel();
    if (!mounted) return;
    setState(() => _isJoined = false);
    _loadRoom();
  }

  @override
  void dispose() {
    if (_isJoined) {
      ApiService.post('/rooms/${widget.roomId}/leave')
          .then<void>((_) {}, onError: (Object _) {});
      AgoraService.leaveChannel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Room')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_room != null) ...[
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(12.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _room?['title'] ?? 'Untitled Room',
                              style: TextStyle(
                                  fontSize: 20.sp, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Host: ${_room?['profiles']?['display_name'] ?? 'Unknown'}',
                              style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              '${_participants.length}/${_room?['max_participants'] ?? 0} participants'
                              '${_isJoined ? ' · $_connectionState' : ''}',
                              style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                            ),
                            SizedBox(height: 16.h),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isJoined ? null : _joinRoom,
                                    child: _joining
                                        ? const SizedBox(
                                            width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2))
                                        : Text(_isJoined ? 'Joined' : 'Join Room'),
                                  ),
                                ),
                                if (_isJoined) ...[
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _leaveRoom,
                                      child: const Text('Leave'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 24.h),
                    Text('Speakers & listeners',
                        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8.h),
                    if (_participants.isEmpty)
                      Text('No participants yet',
                          style: TextStyle(fontSize: 13.sp, color: Colors.grey))
                    else
                      ..._participants.map((p) => ListTile(
                            dense: true,
                            leading: Icon(
                              (p['role'] == 'host' || p['role'] == 'speaker')
                                  ? Icons.mic
                                  : Icons.hearing,
                              color: (p['role'] == 'host' || p['role'] == 'speaker')
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            title: Text('User ${p['user_id']?.toString().substring(0, 8) ?? '?'}',
                                style: TextStyle(fontSize: 14.sp)),
                            trailing: Text(p['role'] ?? 'listener',
                                style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                          )),
                    if (_remoteUid != null)
                      Padding(
                        padding: EdgeInsets.only(top: 8.h),
                        child: Text('Voice connected · remote speaker active',
                            style: TextStyle(fontSize: 12.sp, color: Colors.green)),
                      ),
                  ] else ...[
                    const Center(child: Text('Room not found')),
                  ],
                ],
              ),
            ),
    );
  }
}
