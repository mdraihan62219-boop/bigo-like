import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

/// Submit a reseller recharge request (amount + payment proof screenshot).
class RechargeFromResellerScreen extends StatefulWidget {
  const RechargeFromResellerScreen({super.key});

  @override
  State<RechargeFromResellerScreen> createState() => _RechargeFromResellerScreenState();
}

class _RechargeFromResellerScreenState extends State<RechargeFromResellerScreen> {
  final _amount = TextEditingController();
  XFile? _proof;
  bool _submitting = false;

  Future<void> _pickProof() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null) setState(() => _proof = file);
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid diamond amount')));
      return;
    }
    setState(() => _submitting = true);
    try {
      String? proofUrl;
      if (_proof != null) {
        proofUrl = await StorageService.uploadPostMedia(
            _proof!.path, DateTime.now().microsecondsSinceEpoch.toString());
      }
      await ApiService.post('/reseller/recharge-request', data: {
        'diamonds_requested': amount,
        if (proofUrl != null) 'payment_proof_url': proofUrl,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request submitted — pending approval')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
      setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recharge from Reseller')),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Diamonds requested'),
          ),
          SizedBox(height: 12.h),
          OutlinedButton.icon(onPressed: _pickProof,
              icon: const Icon(Icons.receipt), label: const Text('Payment proof (screenshot)')),
          if (_proof != null) Padding(padding: EdgeInsets.only(top: 8.h),
              child: Chip(label: Text(_proof!.name, overflow: TextOverflow.ellipsis))),
          SizedBox(height: 20.h),
          FilledButton(onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit request')),
        ]),
      ),
    );
  }
}

class MyRechargeRequestsScreen extends StatefulWidget {
  const MyRechargeRequestsScreen({super.key});

  @override
  State<MyRechargeRequestsScreen> createState() => _MyRechargeRequestsScreenState();
}

class _MyRechargeRequestsScreenState extends State<MyRechargeRequestsScreen> {
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiService.get('/reseller/my-requests');
      if (!mounted) return;
      setState(() {
        _requests = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String? s) => switch (s) {
        'approved' => Colors.green,
        'rejected' => Colors.red,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Recharge Requests')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No requests yet')),
                    ])
                  : ListView.builder(
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final r = _requests[index] as Map<String, dynamic>;
                        return ListTile(
                          leading: Icon(Icons.diamond, color: _statusColor(r['status'] as String?), size: 26.r),
                          title: Text('${r['diamonds_requested']} diamonds',
                              style: TextStyle(fontSize: 14.sp)),
                          subtitle: Text('${r['status']} · ${r['created_at'] ?? ''}'.substring(0, 30),
                              style: TextStyle(fontSize: 11.sp)),
                          trailing: Chip(label: Text(r['status'] ?? '', style: TextStyle(fontSize: 11.sp))),
                        );
                      },
                    ),
            ),
    );
  }
}

class HostRequestScreen extends StatefulWidget {
  const HostRequestScreen({super.key});

  @override
  State<HostRequestScreen> createState() => _HostRequestScreenState();
}

class _HostRequestScreenState extends State<HostRequestScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _status;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final response = await ApiService.get('/host-application/me');
      final data = response.data['data'];
      if (!mounted || data == null) return;
      setState(() => _status = data['status'] as String?);
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ApiService.post('/host-application', data: {
        'full_name': _name.text.trim(),
        'phone_number': _phone.text.trim(),
      });
      if (!mounted) return;
      setState(() { _status = 'pending'; _submitting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application submitted!')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_status != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host Application')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_status == 'approved'
                ? Icons.check_circle : _status == 'rejected'
                ? Icons.cancel : Icons.hourglass_top, size: 56.r),
            SizedBox(height: 12.h),
            Text('Application status: ${_status!.toUpperCase()}'),
            if (_status == 'pending')
              Text('We are reviewing your application.',
                  style: TextStyle(color: Colors.grey, fontSize: 12.sp)),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Become a Host')),
      body: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(children: [
          TextField(controller: _name,
              decoration: const InputDecoration(labelText: 'Full name')),
          SizedBox(height: 12.h),
          TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number')),
          SizedBox(height: 20.h),
          FilledButton(onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Apply now')),
        ]),
      ),
    );
  }
}
