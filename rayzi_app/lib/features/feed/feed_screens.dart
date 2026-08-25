import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../utils/api_error.dart';
import '../shared/decorated_widgets.dart';
import '../../presentation/screens/reels_screen.dart' show openReelsViewer;

class NewsfeedScreen extends StatefulWidget {
  const NewsfeedScreen({super.key});

  @override
  State<NewsfeedScreen> createState() => _NewsfeedScreenState();
}

class _NewsfeedScreenState extends State<NewsfeedScreen> {
  String _scope = 'all';
  List<dynamic> _posts = [];
  List<dynamic> _stories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.get('/feed/posts', queryParameters: {'scope': _scope}),
        ApiService.get('/feed/stories'),
      ]);
      if (!mounted) return;
      setState(() {
        _posts = results[0].data['data'] ?? [];
        _stories = results[1].data['data'] ?? [];
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
      appBar: AppBar(
        titleSpacing: 8.w,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10.r),
              child: const Image(
                image: AssetImage('assets/images/logo.jpeg'),
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 8.w),
            const Text('Newsfeed'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.notifications),
          ),
          IconButton(
            icon: Icon(Icons.workspace_premium, color: Colors.amber.shade300),
            tooltip: 'VIP',
            onPressed: () => Navigator.pushNamed(context, '/shop-tier', arguments: 'vip'),
          ),
          Padding(
            padding: EdgeInsets.only(right: 10.w, left: 2.w),
            child: TextButton(
              onPressed: () async {
                await Navigator.pushNamed(context, AppRoutes.createPost);
                _load();
              },
              child: Text('POST',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(44.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'timeline', label: Text('Timeline')),
              ],
              selected: {_scope},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                _load();
              },
              showSelectedIcon: false,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _posts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildStoryBar();
                  return PostCard(post: _posts[index - 1], onChanged: _load);
                },
              ),
            ),
    );
  }

  Widget _buildStoryBar() {
    return SizedBox(
      height: 96.h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        itemCount: _stories.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: EdgeInsets.only(right: 10.w),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/create-story'),
                    child: CircleAvatar(
                      radius: 28.r,
                      child: Icon(Icons.add, size: 26.r),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text('Add', style: TextStyle(fontSize: 10.sp)),
                ],
              ),
            );
          }
          final group = _stories[index - 1] as Map<String, dynamic>;
          final author = group['author'] as Map<String, dynamic>? ?? {};
          return Padding(
            padding: EdgeInsets.only(right: 10.w),
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/story-viewer',
                  arguments: group),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(2.r),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFFFF6B9D), Color(0xFFF5C518)]),
                    ),
                    child: CircleAvatar(
                      radius: 27.r,
                      backgroundColor: Colors.black,
                      backgroundImage: author['avatar_url'] != null
                          ? CachedNetworkImageProvider(author['avatar_url'] as String)
                          : null,
                      child: author['avatar_url'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  SizedBox(
                    width: 56.w,
                    child: Text(author['username'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10.sp)),
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

class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, this.onChanged});
  final Map<String, dynamic> post;
  final VoidCallback? onChanged;

  Future<void> _like(BuildContext context) async {
    try {
      await ApiService.post('/feed/posts/${post['id']}/like');
      onChanged?.call();
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _comment(BuildContext context) async {
    final controller = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(hintText: 'Write a comment…'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () => Navigator.pop(context, true),
            ),
          ]),
        ),
      ),
    );
    if (sent == true && controller.text.trim().isNotEmpty) {
      try {
        await ApiService.post('/feed/posts/${post['id']}/comments',
            data: {'content': controller.text.trim()});
        onChanged?.call();
      } catch (e) {
        if (context.mounted) showApiError(context, e);
      }
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final author = post['profiles'] as Map<String, dynamic>? ?? {};
    final urls = post['media_urls'] as List<dynamic>? ?? [];
    final isVideo = post['media_type'] == 'video' && urls.isNotEmpty;
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: DecoratedAvatar(avatarUrl: author['avatar_url'] as String?, radius: 18),
            title: DecoratedUsername(profile: author, baseStyle: TextStyle(fontSize: 14.sp)),
            subtitle: Text(_timeAgo(post['created_at'] as String?), style: TextStyle(fontSize: 11.sp)),
          ),
          if ((post['content'] as String?)?.isNotEmpty == true)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Text(post['content'] as String, style: TextStyle(fontSize: 13.sp)),
            ),
          if (!isVideo && urls.isNotEmpty)
            AspectRatio(
              aspectRatio: urls.length > 1 ? 1.5 : 1.2,
              child: CachedNetworkImage(imageUrl: urls.first as String, fit: BoxFit.cover),
            )
          else if (isVideo)
            GestureDetector(
              onTap: () => openReelsViewer(context, [post], 0),
              child: Stack(alignment: Alignment.center, children: [
                AspectRatio(
                  aspectRatio: 1.4,
                  child: Container(color: Colors.black54),
                ),
                const Icon(Icons.play_circle_fill, size: 52, color: Colors.white70),
              ]),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => _like(context),
                icon: const Icon(Icons.favorite_border, size: 18),
                label: Text('${post['likes_count'] ?? 0}', style: TextStyle(fontSize: 12.sp)),
              ),
              TextButton.icon(
                onPressed: () => _comment(context),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text('${post['comments_count'] ?? 0}', style: TextStyle(fontSize: 12.sp)),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.share_outlined, size: 18), onPressed: () {}),
            ]),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Create a text + optional image/video post.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _controller = TextEditingController();
  XFile? _media;
  bool _submitting = false;

  Future<void> _pick(bool video) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _media = file);
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty && _media == null) return;
    setState(() => _submitting = true);
    try {
      List<String> mediaUrls = [];
      String mediaType = 'image';
      if (_media != null) {
        final url = await StorageService.uploadPostMedia(_media!.path, DateTime.now().microsecondsSinceEpoch.toString());
        mediaUrls = [url];
        mediaType = _media!.path.toLowerCase().endsWith('.mp4') ? 'video' : 'image';
      }
      await ApiService.post('/feed/posts', data: {
        'content': _controller.text.trim(),
        if (mediaUrls.isNotEmpty) ...{'media_urls': mediaUrls, 'media_type': mediaType},
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Posting…' : 'Post'),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(children: [
          TextField(
            controller: _controller,
            maxLines: 5,
            decoration: const InputDecoration(hintText: "What's on your mind?"),
          ),
          SizedBox(height: 12.h),
          Row(children: [
            OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.image), label: const Text('Photo')),
            SizedBox(width: 12.w),
            OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.videocam), label: const Text('Video')),
          ]),
          if (_media != null)
            Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: Chip(label: Text(_media!.name, overflow: TextOverflow.ellipsis)),
            ),
        ]),
      ),
    );
  }
}

/// Uploads a 24-hour story (image or video).
class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  XFile? _media;
  bool _submitting = false;

  Future<void> _pick(bool video) async {
    final picker = ImagePicker();
    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _media = file);
  }

  Future<void> _submit() async {
    if (_media == null) return;
    setState(() => _submitting = true);
    try {
      final url = await StorageService.uploadPostMedia(_media!.path, DateTime.now().microsecondsSinceEpoch.toString());
      await ApiService.post('/feed/stories', data: {
        'media_url': url,
        'media_type': _media!.path.toLowerCase().endsWith('.mp4') ? 'video' : 'image',
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Story')),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(children: [
          Row(children: [
            OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.image), label: const Text('Photo')),
            SizedBox(width: 12.w),
            OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.videocam), label: const Text('Video')),
          ]),
          if (_media != null)
            Padding(padding: EdgeInsets.only(top: 12.h), child: Chip(label: Text(_media!.name))),
          SizedBox(height: 12.h),
          FilledButton(onPressed: _media == null || _submitting ? null : _submit,
              child: Text(_submitting ? 'Uploading…' : 'Share story')),
        ]),
      ),
    );
  }
}
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key});
  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;
  int _storyIndex = 0;
  List<dynamic> _stories = [];

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      })
      ..forward();
  }

  void _next() {
    if (_storyIndex + 1 < _stories.length) {
      setState(() => _storyIndex++);
      _progress.forward(from: 0);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && _stories.isEmpty) {
      _stories = (args['stories'] as List?) ?? [args];
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = _stories.isEmpty ? {} : _stories[_storyIndex] as Map<String, dynamic>;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ApiService.post('/feed/stories/${story['id']}/view');
      } catch (_) {}
    });
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _next,
        child: Stack(fit: StackFit.expand, children: [
          CachedNetworkImage(imageUrl: story['media_url'] as String? ?? '', fit: BoxFit.contain),
          SafeArea(
            child: Column(children: [
              LinearProgressIndicator(value: _progress.value, minHeight: 3.h),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(story['author_id']?.toString().substring(0, 8) ?? 'Story',
                    style: const TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
