import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../../services/reels_service.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.posts, this.initialIndex = 0, this.embedded = false});

  final List<dynamic>? posts;
  final int initialIndex;

  /// Embedded mode (home tab): no top bar / back button.
  final bool embedded;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  late PageController _pageController;
  late List<dynamic> _posts;
  late bool _isLoading;
  String? _error;
  final Map<int, VideoPlayerController?> _controllers = {};
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _posts = widget.posts ?? [];
    _isLoading = widget.posts == null;
    if (widget.posts != null) {
      // Warm up the first video immediately.
      setState(() {});
    } else {
      _loadReels();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c?.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadReels() async {
    try {
      final data = await ReelsService.loadVideoPosts();
      if (!mounted) return;
      setState(() {
        _posts = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  VideoPlayerController? _controllerFor(int index) {
    if (_controllers.containsKey(index)) return _controllers[index];
    final urls = (_posts[index]['media_urls'] as List<dynamic>?);
    if (urls == null || urls.isEmpty) {
      _controllers[index] = null;
      return null;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(urls.first as String));
    _controllers[index] = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      controller.play();
      setState(() {});
    }).catchError((Object _) {
      if (!mounted) return;
      setState(() {});
    });
    return null;
  }

  void _onPageChanged(int index) {
    _controllers.removeWhere((i, c) {
      if ((index - i).abs() > 1) {
        c?.dispose();
        return true;
      }
      c?.pause();
      return false;
    });
    final current = _controllers[index];
    if (current != null && current.value.isInitialized) {
      current.play();
    }
    setState(() {});
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final id = post['id'] as String;
    final wasLiked = _likedIds.contains(id);
    setState(() {
      if (wasLiked) {
        _likedIds.remove(id);
        post['likes_count'] = ((post['likes_count'] as num?) ?? 1) - 1;
      } else {
        _likedIds.add(id);
        post['likes_count'] = ((post['likes_count'] as num?) ?? 0) + 1;
      }
    });
    try {
      if (wasLiked) {
        await ApiService.delete('/posts/$id/like');
      } else {
        await ApiService.post('/posts/$id/like');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _likedIds.add(id);
          post['likes_count'] = ((post['likes_count'] as num?) ?? 0) + 1;
        } else {
          _likedIds.remove(id);
          post['likes_count'] = ((post['likes_count'] as num?) ?? 1) - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _posts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Reels'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_creation_outlined, size: 64.w, color: Colors.white24),
              SizedBox(height: 12.h),
              Text(
                _error != null ? 'Could not load reels' : 'No reels yet',
                style: TextStyle(color: Colors.white54, fontSize: 14.sp),
              ),
              SizedBox(height: 16.h),
              TextButton(onPressed: _loadReels, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _posts.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _buildReelTile(index),
      ),
    );
  }

  Widget _buildReelTile(int index) {
    final post = _posts[index] as Map<String, dynamic>;
    final profile = post['profiles'] as Map<String, dynamic>?;
    final controller = _controllerFor(index);
    final initialized = controller?.value.isInitialized ?? false;
    final liked = _likedIds.contains(post['id']);

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () {
            final c = _controllers[index];
            if (c == null) return;
            if (c.value.isPlaying) {
              c.pause();
            } else {
              c.play();
            }
            setState(() {});
          },
          child: initialized
              ? Center(child: AspectRatio(aspectRatio: controller!.value.aspectRatio, child: VideoPlayer(controller)))
              : const Center(child: CircularProgressIndicator(color: Colors.white54)),
        ),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 16.w, right: 76.w, bottom: 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16.r,
                          backgroundImage: (profile?['avatar_url'] as String?)?.isNotEmpty == true
                              ? NetworkImage(profile!['avatar_url'] as String)
                              : null,
                          child: (profile?['avatar_url'] as String?)?.isNotEmpty != true
                              ? Icon(Icons.person, size: 18.r)
                              : null,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          '@${profile?['username'] ?? 'user'}',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.sp),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      post['content'] as String? ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 13.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12.w,
          bottom: 60.h,
          child: Column(
            children: [
              _ReelAction(
                icon: liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? Colors.red : Colors.white,
                label: '${post['likes_count'] ?? 0}',
                onTap: () => _toggleLike(post),
              ),
              SizedBox(height: 18.h),
              _ReelAction(
                icon: Icons.chat_bubble_outline,
                color: Colors.white,
                label: '${post['comments_count'] ?? 0}',
                onTap: () {},
              ),
              SizedBox(height: 18.h),
              _ReelAction(
                icon: Icons.share_outlined,
                color: Colors.white,
                label: '${post['shares_count'] ?? 0}',
                onTap: () {},
              ),
            ],
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8.h,
          left: 16.w,
          child: widget.embedded
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22.r),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
        ),
        if (!widget.embedded)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8.h,
            left: MediaQuery.of(context).size.width / 2 - 40.w,
            child: Text('Reels', style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _ReelAction extends StatelessWidget {
  const _ReelAction({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24.r),
      child: Padding(
        padding: EdgeInsets.all(4.r),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30.r),
            SizedBox(height: 4.h),
            Text(label, style: TextStyle(color: Colors.white, fontSize: 11.sp)),
          ],
        ),
      ),
    );
  }
}

/// Opens the full-screen reel viewer for [posts] starting at [index].
void openReelsViewer(BuildContext context, List<dynamic> posts, int index) {
  Navigator.pushNamed(context, AppRoutes.reels,
      arguments: {'posts': posts, 'initialIndex': index});
}

/// Home-tab wrapper around the reels viewer.
class ReelsTab extends StatelessWidget {
  const ReelsTab({super.key});

  @override
  Widget build(BuildContext context) => const ReelsScreen(embedded: true);
}
