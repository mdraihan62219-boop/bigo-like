import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';
import 'reels_screen.dart';

class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  List<dynamic> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    try {
      final response = await ApiService.get('/posts');
      setState(() {
        _posts = response.data['data'] ?? [];
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
      appBar: AppBar(title: const Text('Explore')),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadPosts,
            child: _posts.isEmpty
              ? ListView(children: const [SizedBox(height: 200), Center(child: Text('No posts yet'))])
                : GridView.builder(
                  padding: EdgeInsets.all(8.w),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    final urls = post['media_urls'] as List<dynamic>?;
                    final isVideo = post['media_type'] == 'video';
                    return GestureDetector(
                      onTap: () {
                        if (!isVideo) return;
                        final videoPosts =
                            _posts.where((p) => p['media_type'] == 'video').toList();
                        openReelsViewer(context, videoPosts, videoPosts.indexOf(post));
                      },
                      child: ClipRRect(
                      borderRadius: BorderRadius.circular(6.r),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: (urls != null && urls.isNotEmpty)
                              ? urls.first
                              : 'https://via.placeholder.com/200',
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                          ),
                          if (isVideo)
                            const Center(
                              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.favorite, size: 14, color: Colors.white),
                                  SizedBox(width: 2.w),
                                  Text('${post['likes_count'] ?? 0}',
                                    style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
    );
  }
}
