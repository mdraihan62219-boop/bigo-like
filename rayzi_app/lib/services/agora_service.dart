import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';

/// Thrown instead of a raw AgoraRtcException(-101) when the app was built
/// without a real AGORA_APP_ID dart-define.
class AgoraConfigurationException implements Exception {
  final String message;
  const AgoraConfigurationException([this.message =
      'Agora is not configured. Build with --dart-define=AGORA_APP_ID=<your-real-app-id>']);
  @override
  String toString() => message;
}

class AgoraService {
  static RtcEngine? _engine;

  static bool get isConfigured => AppConstants.agoraAppId.isNotEmpty;

  static Future<void> initialize() async {
    if (_engine != null) return;
    if (!isConfigured) throw const AgoraConfigurationException();
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: AppConstants.agoraAppId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
  }

  static Future<void> requestPermissions() async {
    await [Permission.camera, Permission.microphone].request();
  }

  static Future<void> joinChannel(String channelName, String token, int uid, bool isHost) async {
    await _engine!.setClientRole(
      role: isHost ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
    );

    await _engine!.enableVideo();
    if (isHost) {
      await _engine!.startPreview();
    }

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  /// Voice-only join for Audio Rooms. Shares the same engine/token service
  /// as live streaming; video stays off so only microphone audio publishes.
  static Future<void> joinAudioChannel(
    String channelName,
    String token,
    int uid,
    bool canPublish,
  ) async {
    await _engine!.setClientRole(
      role: canPublish ? ClientRoleType.clientRoleBroadcaster : ClientRoleType.clientRoleAudience,
    );

    await _engine!.disableVideo();
    await _engine!.enableAudio();
    // A previous video session may have left the local camera publishing;
    // force-mute so an audio-room join never leaks camera frames.
    await _engine!.muteLocalVideoStream(true);

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(),
    );
  }

  static Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
    await _engine?.stopPreview();
  }

  static Future<void> dispose() async {
    await _engine?.release();
    _engine = null;
  }

  static RtcEngine? get engine => _engine;
}
