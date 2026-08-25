import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.get('/wallet/ledger');
      setState(() {
        _items = res.data['data'] is List ? res.data['data'] : [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Failed to load history: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(child: Text('No history yet', style: TextStyle(fontSize: 14.sp, color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: EdgeInsets.all(16.w),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index] as Map<String, dynamic>;
                          final amount = item['amount'] ?? 0;
                          final reason = item['reason'] ?? '';
                          final createdAt = item['created_at'] ?? '';
                          final isCredit = (amount as num) > 0;
                          return Card(
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: ListTile(
                              leading: Icon(
                                isCredit ? Icons.add_circle : Icons.remove_circle,
                                color: isCredit ? Colors.green : Colors.red,
                              ),
                              title: Text(reason.toString().replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(fontSize: 14.sp)),
                              subtitle: Text(createdAt.toString().substring(0, createdAt.toString().length > 19 ? 19 : createdAt.toString().length),
                                  style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                              trailing: Text(
                                '${isCredit ? '+' : ''}$amount',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                  color: isCredit ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
