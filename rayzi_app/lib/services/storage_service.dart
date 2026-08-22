import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  static final _client = Supabase.instance.client;
  static const _uuid = Uuid();

  static Future<String> uploadAvatar(String filePath, String userId) async {
    final fileName = 'avatar_$userId.jpg';
    await _client.storage.from('avatars').upload(fileName, File(filePath), fileOptions: const FileOptions(upsert: true));
    return _client.storage.from('avatars').getPublicUrl(fileName);
  }

  static Future<String> uploadStreamThumbnail(String filePath, String streamId) async {
    final fileName = 'thumb_$streamId.jpg';
    await _client.storage.from('stream-thumbnails').upload(fileName, File(filePath), fileOptions: const FileOptions(upsert: true));
    return _client.storage.from('stream-thumbnails').getPublicUrl(fileName);
  }

  static Future<String> uploadPostMedia(String filePath, String postId) async {
    final ext = filePath.split('.').last;
    final fileName = '${_uuid.v4()}.$ext';
    await _client.storage.from('post-media').upload(fileName, File(filePath));
    return _client.storage.from('post-media').getPublicUrl(fileName);
  }
}
