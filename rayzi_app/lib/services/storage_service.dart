import 'package:dio/dio.dart';
import 'api_service.dart';

/// Uploads media through the backend's JWT-authenticated proxy
/// (POST /api/v1/uploads). App users hold a custom backend JWT, not a
/// Supabase session, so direct client → Storage uploads are denied by
/// storage RLS — the backend writes with its service role instead.
class StorageService {
  static Future<String> _upload({
    required String filePath,
    required String bucket,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'bucket': bucket,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await ApiService.post('/uploads', data: form);
    final url = response.data['data']?['url'] as String?;
    if (url == null || url.isEmpty) throw Exception('Upload failed: no URL returned');
    return url;
  }

  static Future<String> uploadAvatar(String filePath, String userId) =>
      _upload(filePath: filePath, bucket: 'avatars', fileName: 'avatar_$userId.jpg');

  static Future<String> uploadStreamThumbnail(String filePath, String streamId) =>
      _upload(filePath: filePath, bucket: 'stream-thumbnails', fileName: 'thumb_$streamId.jpg');

  static Future<String> uploadPostMedia(String filePath, String postId) {
    final ext = filePath.split('.').last.toLowerCase();
    return _upload(filePath: filePath, bucket: 'post-media', fileName: '$postId.$ext');
  }

  static Future<String> uploadGiftAnimation(String filePath, String giftId) =>
      _upload(filePath: filePath, bucket: 'gift-animations', fileName: 'gift_$giftId.gif');

  static Future<String> uploadRoomCover(String filePath, String roomId) =>
      _upload(filePath: filePath, bucket: 'room-covers', fileName: 'cover_$roomId.jpg');
}
