import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/constants.dart';

class AgoraService {
  static RtcEngine? _engine;

  static Future<void> initialize() async {
    if (_engine != null) return;
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
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
      options: ChannelMediaOptions(),
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
