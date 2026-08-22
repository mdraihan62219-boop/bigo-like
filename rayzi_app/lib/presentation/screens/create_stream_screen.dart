import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

class CreateStreamScreen extends StatefulWidget {
  const CreateStreamScreen({super.key});

  @override
  State<CreateStreamScreen> createState() => _CreateStreamScreenState();
}

class _CreateStreamScreenState extends State<CreateStreamScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'general';
  bool _isPrivate = false;
  bool _creating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    setState(() => _creating = true);
    try {
      final response = await ApiService.post('/streams', data: {
        'title': _titleController.text,
        'description': _descriptionController.text,
        'category': _category,
        'is_private': _isPrivate,
      });
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/stream', arguments: response.data['data']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create stream: $e')),
        );
      }
    }
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Go Live')),
      body: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          children: [
            CustomTextField(controller: _titleController, hint: 'Stream Title'),
            SizedBox(height: 16.h),
            CustomTextField(controller: _descriptionController, hint: 'Description', maxLines: 3),
            SizedBox(height: 16.h),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF16213E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
              ),
              items: ['general', 'gaming', 'music', 'talk', 'sports']
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'general'),
            ),
            SizedBox(height: 16.h),
            SwitchListTile(
              title: const Text('Private Stream'),
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v),
            ),
            SizedBox(height: 24.h),
            CustomButton(text: 'Start Streaming', onPressed: _creating ? null : _create),
          ],
        ),
      ),
    );
  }
}
