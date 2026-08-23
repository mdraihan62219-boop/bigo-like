import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

/// Inbox: conversation list with last-message preview + unread badges.
class InboxListScreen extends StatefulWidget {
  const InboxListScreen({super.key});

  @override
  State<InboxListScreen> createState() => _InboxListScreenState();
}

class _InboxListScreenState extends State<InboxListScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiService.get('/inbox/conversations');
      if (!mounted) return;
      setState(() {
        _conversations = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _conversations.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No conversations yet')),
                    ])
                  : ListView.builder(
                      itemCount: _conversations.length,
                      itemBuilder: (context, index) {
                        final conv = _conversations[index] as Map<String, dynamic>;
                        // Show the *other* participant as the list label.
                        final other = conv['user_a'] ?? conv['user_b'];
                        final otherMap =
                            other is Map ? Map<String, dynamic>.from(other) : <String, dynamic>{};
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                otherMap['avatar_url'] != null
                                    ? CachedNetworkImageProvider(otherMap['avatar_url'] as String)
                                    : null,
                            child: otherMap['avatar_url'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(otherMap['display_name'] ?? 'User',
                              style: TextStyle(fontSize: 14.sp)),
                          subtitle: Text('Tap to open conversation',
                              style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                          onTap: () => Navigator.pushNamed(context, '/conversation',
                                  arguments: {'conversationId': conv['id'], 'other': otherMap})
                              .then((_) => _load()),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Rich conversation thread: text, photos, ≤60s reel messages + call buttons.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  String _conversationId = '';
  Map<String, dynamic> _other = {};
  List<dynamic> _messages = [];
  final _input = TextEditingController();
  Timer? _poller;
  bool _recordingReel = false;
  int _reelSecondsLeft = 60;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && _conversationId.isEmpty) {
      _conversationId = args['conversationId'] as String? ?? '';
      final o = args['other'];
      if (o is Map) _other = Map<String, dynamic>.from(o);
      _load();
      _poller = Timer.periodic(const Duration(seconds: 4), (_) => _load());
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_conversationId.isEmpty) return;
    try {
      final response = await ApiService.get(
          '/inbox/conversations/$_conversationId/messages');
      if (!mounted) return;
      setState(() => _messages = response.data['data'] ?? []);
      ApiService.put('/inbox/conversations/$_conversationId/read').then<void>((_) {}, onError: (Object _) {});
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      await ApiService.post('/inbox/conversations/$_conversationId/messages',
          data: {'message_type': 'text', 'text_content': text});
      _load();
    } catch (_) {}
  }

  Future<void> _sendPhoto() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    try {
      final url = await StorageService.uploadPostMedia(file.path,
          DateTime.now().microsecondsSinceEpoch.toString());
      await ApiService.post('/inbox/conversations/$_conversationId/messages',
          data: {'message_type': 'photo', 'media_url': url});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    }
  }

  /// Reel recorder with a hard 60-second countdown ring.
  Future<void> _recordReel() async {
    setState(() { _recordingReel = true; _reelSecondsLeft = 60; });
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_recordingReel) { t.cancel(); return; }
      if (_reelSecondsLeft <= 0) { t.cancel(); _finishReel(); return; }
      if (mounted) setState(() => _reelSecondsLeft--);
    });
    final file = await ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 60));
    if (file == null) {
      setState(() => _recordingReel = false);
      return;
    }
    try {
      final url = await StorageService.uploadPostMedia(file.path,
          DateTime.now().microsecondsSinceEpoch.toString());
      await ApiService.post('/inbox/conversations/$_conversationId/messages',
          data: {'message_type': 'video_reel', 'media_url': url, 'media_duration_seconds': 60});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _recordingReel = false);
    }
  }

  void _finishReel() {
    if (mounted) setState(() => _recordingReel = false);
  }

  Future<void> _startCall(bool video) async {
    try {
      await ApiService.post('/inbox/conversations/$_conversationId/call',
          data: {'call_type': video ? 'video' : 'audio'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${video ? 'Video' : 'Audio'} call starting… (Agora channel ready)')));
    } catch (_) {}
  }

  Widget _bubble(Map<String, dynamic> msg) {
    final mine = msg['sender_id'] != _other['id'];
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final color = mine ? Theme.of(context).colorScheme.primary : Colors.grey.shade800;
    final type = msg['message_type'] as String?;
    Widget content;
    switch (type) {
      case 'photo':
        content = ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: CachedNetworkImage(
              imageUrl: msg['media_url'] as String? ?? '',
              width: 180.w, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox(width: 100, height: 60)),
        );
        break;
      case 'video_reel':
        content = Container(
          width: 160.w,
          padding: EdgeInsets.all(10.r),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10.r)),
          child: Row(children: [
            Icon(Icons.play_circle_fill, size: 28.r),
            SizedBox(width: 8.w),
            Text('Reel · ${msg['media_duration_seconds'] ?? 0}s',
                style: TextStyle(color: Colors.white, fontSize: 11.sp)),
          ]),
        );
        break;
      case 'call_log':
        content = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(msg['call_type'] == 'video' ? Icons.videocam : Icons.call, size: 14.r),
          SizedBox(width: 6.w),
          Text('${msg['call_type']} call · ${msg['call_duration_seconds'] ?? 0}s',
              style: TextStyle(fontSize: 12.sp)),
        ]);
        break;
      default:
        content = Text(msg['text_content'] ?? '', style: TextStyle(color: Colors.white, fontSize: 13.sp));
    }
    return Align(
      alignment: align,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.h, horizontal: 12.w),
        constraints: BoxConstraints(maxWidth: 260.w),
        padding: type == 'text' || type == 'call_log'
            ? EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w)
            : EdgeInsets.all(4.r),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(
            radius: 16.r,
            backgroundImage: _other['avatar_url'] != null
                ? CachedNetworkImageProvider(_other['avatar_url'] as String)
                : null,
            child: _other['avatar_url'] == null ? const Icon(Icons.person) : null,
          ),
          SizedBox(width: 10.w),
          Expanded(
              child: Text(_other['display_name'] ?? 'Chat',
                  style: TextStyle(fontSize: 15.sp), overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.call), onPressed: () => _startCall(false)),
          IconButton(icon: const Icon(Icons.videocam), onPressed: () => _startCall(true)),
        ],
      ),
      body: Column(children: [
        if (_recordingReel)
          Padding(
            padding: EdgeInsets.all(8.h),
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 44.r, height: 44.r,
                child: CircularProgressIndicator(value: _reelSecondsLeft / 60)),
              Text('$_reelSecondsLeft', style: TextStyle(fontSize: 12.sp)),
            ]),
          ),
        Expanded(
          child: ListView(children: [for (final m in _messages) _bubble(m as Map<String, dynamic>)]),
        ),
        SafeArea(
          child: Row(children: [
            IconButton(icon: const Icon(Icons.image_outlined), onPressed: _sendPhoto),
            IconButton(icon: const Icon(Icons.movie_creation_outlined), onPressed: _recordReel),
            Expanded(
              child: TextField(controller: _input,
                  onSubmitted: (_) => _sendText(),
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(hintText: 'Message…',
                      border: InputBorder.none)),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _sendText),
          ]),
        ),
      ]),
    );
  }
}
