import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

class ReelsService {
  /// Loads video posts for the reels feed.
  ///
  /// Tries the API first (supports the media_type filter once the backend
  /// redeploy lands). Falls back to a direct Supabase read — RLS allows
  /// public SELECT on posts, so guests always get a working feed.
  static Future<List<dynamic>> loadVideoPosts() async {
    try {
      final response = await ApiService.get('/posts', queryParameters: {
        'media_type': 'video',
        'limit': 50,
      });
      final data = response.data['data'];
      if (data is List && data.isNotEmpty) return data;
    } catch (_) {
      // fall through to Supabase
    }
    return _loadFromSupabase();
  }

  static Future<List<dynamic>> _loadFromSupabase() async {
    final client = Supabase.instance.client;
    final data = await client
        .from('posts')
        .select('*, profiles!posts_user_id_fkey(username, display_name, avatar_url)')
        .eq('media_type', 'video')
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List).toList();
  }
}
