import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/api_service.dart';
import '../../config/routes.dart';
import '../../utils/api_error.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({super.key});

  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  List<dynamic> _streams = [];
  bool _isLoading = true;
  String _filter = 'all'; // all | video | audio | following

  @override
  void initState() {
    super.initState();
    _loadStreams();
  }

  Future<void> _loadStreams() async {
    setState(() => _isLoading = true);
    try {
      final queryParameters = <String, dynamic>{'status': 'live'};
      if (_filter == 'video') {
        // Video-only: live streams (camera) — rooms are audio.
      } else if (_filter == 'audio') {
        final response = await ApiService.get('/rooms');
        if (!mounted) return;
        setState(() {
          _streams = response.data['data'] ?? [];
          _isLoading = false;
        });
        return;
      } else if (_filter == 'following') {
        queryParameters['following'] = 'true';
      }
      final response = await ApiService.get('/streams', queryParameters: queryParameters);
      setState(() {
        _streams = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Streams'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.search),
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.notifications),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: SizedBox(
              height: 36.h,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['all', 'video', 'audio', 'following'].map((f) {
                  final selected = _filter == f;
                  return Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: ChoiceChip(
                      label: Text(f[0].toUpperCase() + f.substring(1)),
                      selected: selected,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _loadStreams();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadStreams,
                child: _streams.isEmpty
                  ? ListView(children: const [SizedBox(height: 200), Center(child: Text('No live streams'))])
                  : GridView.builder(
                  padding: EdgeInsets.all(12.w),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 12.w,
                    mainAxisSpacing: 12.h,
                  ),
                  itemCount: _streams.length,
                  itemBuilder: (context, index) {
                    final stream = _streams[index];
                    return GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context, AppRoutes.stream,
                        arguments: stream,
                      ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: stream['thumbnail_url'] ?? 'https://via.placeholder.com/300',
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4.r),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6.w, height: 6.h,
                                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          ),
                                          SizedBox(width: 4.w),
                                          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4.r),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.visibility, size: 14, color: Colors.white),
                                          SizedBox(width: 4.w),
                                          Text('${stream['current_viewers'] ?? 0}', style: TextStyle(color: Colors.white, fontSize: 10.sp)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(8.w),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stream['title'] ?? 'Untitled Stream',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    stream['profiles']?['display_name'] ?? 'Unknown',
                                    style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                                  ),
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
          ),
        ],
      ),
    );
  }
}
