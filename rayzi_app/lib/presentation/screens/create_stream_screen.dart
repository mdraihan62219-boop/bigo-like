import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import '../../services/agora_service.dart';
import '../../utils/api_error.dart';

class CreateStreamScreen extends StatefulWidget {
  const CreateStreamScreen({super.key});

  @override
  State<CreateStreamScreen> createState() => _CreateStreamScreenState();
}

class _CreateStreamScreenState extends State<CreateStreamScreen> {
  bool _cameraReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        if (mounted) setState(() => _error = 'Camera and microphone permissions are required');
        return;
      }
      await AgoraService.initialize();
      await AgoraService.engine!.enableVideo();
      await AgoraService.engine!.startPreview();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to initialize camera: ${friendlyError(e)}');
    }
  }

  Future<void> _startStream(String type) async {
    if (!mounted) return;
    try {
      final response = await ApiService.post('/streams', data: {
        'title': 'Live Stream',
        'description': '',
        'category': 'general',
        'is_private': false,
        'stream_type': type,
      });
      if (mounted && response.data['data'] != null) {
        Navigator.pushReplacementNamed(context, '/stream', arguments: response.data['data']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start stream: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  void dispose() {
    AgoraService.leaveChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview behind everything.
          if (_cameraReady)
            Center(child: AgoraService.engine != null ? _buildPreview() : const SizedBox())
          else if (_error != null)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_off, size: 64.r, color: Colors.white54),
                    SizedBox(height: 16.h),
                    Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                    SizedBox(height: 16.h),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
                  ],
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Close button top-left.
          Positioned(
            top: 48.h,
            left: 16.w,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // "Choose Type" bottom sheet overlay.
          if (_cameraReady)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildTypePicker(),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final engine = AgoraService.engine!;
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget _buildTypePicker() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withAlpha((0.8 * 255).round())],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose Type',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            SizedBox(height: 24.h),
            Row(
              children: [
                Expanded(child: _buildTypeOption(
                  icon: Icons.mic,
                  label: 'Audio Live',
                  onTap: () => _startStream('audio'),
                )),
                SizedBox(width: 16.w),
                Expanded(child: _buildTypeOption(
                  icon: Icons.videocam,
                  label: 'Video Live',
                  onTap: () => _startStream('video'),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha((0.15 * 255).round()),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40.r, color: Colors.white),
            SizedBox(height: 8.h),
            Text(label, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
