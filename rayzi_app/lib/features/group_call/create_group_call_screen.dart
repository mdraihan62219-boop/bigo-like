import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class CreateGroupCallScreen extends StatefulWidget {
  const CreateGroupCallScreen({super.key});

  @override
  State<CreateGroupCallScreen> createState() => _CreateGroupCallScreenState();
}

class _CreateGroupCallScreenState extends State<CreateGroupCallScreen> {
  final _titleController = TextEditingController(text: 'Group Call');
  String _category = 'general';
  int _maxSeats = 9;
  bool _isPrivate = false;
  bool _creating = false;

  static const _categories = [
    'general', 'music', 'gaming', 'talk', 'dating', 'talent',
  ];

  Future<void> _create() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() => _creating = true);
    try {
      await [Permission.camera, Permission.microphone].request();
      final res = await ApiService.post('/group-calls', data: {
        'title': _titleController.text.trim(),
        'category': _category,
        'max_seats': _maxSeats,
        'is_private': _isPrivate,
      });
      if (!mounted) return;
      final roomId = res.data['data']['id'] as String;
      Navigator.pushReplacementNamed(context, '/group-call-room',
          arguments: {'roomId': roomId});
    } catch (e) {
      if (!mounted) return;
      showApiError(context, e);
      setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start Group Call')),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: ListView(
          children: [
            Text('Room Title', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'e.g. Chill & Chat',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
            ),
            SizedBox(height: 20.h),
            Text('Category', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: _categories.map((cat) {
                final selected = _category == cat;
                return ChoiceChip(
                  label: Text(cat[0].toUpperCase() + cat.substring(1)),
                  selected: selected,
                  onSelected: (_) => setState(() => _category = cat),
                );
              }).toList(),
            ),
            SizedBox(height: 20.h),
            Text('Max Seats: $_maxSeats', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            Slider(
              value: _maxSeats.toDouble(),
              min: 4,
              max: 12,
              divisions: 8,
              label: '$_maxSeats seats',
              onChanged: (v) => setState(() => _maxSeats = v.round()),
            ),
            SizedBox(height: 20.h),
            SwitchListTile(
              title: const Text('Private Room'),
              subtitle: const Text('Require password to join'),
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            SizedBox(height: 30.h),
            FilledButton(
              onPressed: _creating ? null : _create,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 14.h),
              ),
              child: _creating
                  ? SizedBox(width: 20.r, height: 20.r,
                      child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Start Group Call', style: TextStyle(fontSize: 15.sp)),
            ),
          ],
        ),
      ),
    );
  }
}
