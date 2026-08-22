import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MessagesTab extends StatelessWidget {
  const MessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message, size: 64.w, color: Colors.grey),
            SizedBox(height: 16.h),
            Text('No conversations yet',
              style: TextStyle(fontSize: 16.sp, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
