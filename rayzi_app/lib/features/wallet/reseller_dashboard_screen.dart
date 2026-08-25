import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'wallet_v2_screens.dart' show showWalletSnackBar;
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

/// RESELLER DASHBOARD — visible only to accounts with an active
/// reseller_agents row. Shows their shareable code, credit balance,
/// pending requests submitted TO THEM, and recent credit-pool ledger.
/// Approve/reject call the scoped endpoints; ownership checks live in
/// the RPC so a reseller can never touch another reseller's request.
class ResellerDashboardScreen extends StatefulWidget {
  const ResellerDashboardScreen({super.key});

  @override
  State<ResellerDashboardScreen> createState() => _ResellerDashboardScreenState();
}

class _ResellerDashboardScreenState extends State<ResellerDashboardScreen> {
  Map<String, dynamic>? _agent;
  List<dynamic> _pending = [];
  List<dynamic> _ledger = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.get('/reseller/dashboard');
      if (!mounted) return;
      final data = res.data['data'] as Map<String, dynamic>;
      setState(() {
        _agent = data['agent'] as Map<String, dynamic>?;
        _pending = data['pending_requests'] ?? [];
        _ledger = data['recent_ledger'] ?? [];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _approve(String id) async {
    try {
      await ApiService.post('/reseller/requests/$id/approve');
      if (!mounted) return;
      showWalletSnackBar(context, 'Request approved — diamonds credited');
      _load();
    } catch (e) {
      if (!mounted) return;
      showWalletSnackBar(context, 'Approve failed: ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _reject(String id) async {
    final reasonController = TextEditingController(text: 'Rejected by reseller');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.post('/reseller/requests/$id/reject',
          data: {'reason': reasonController.text.trim()});
      if (!mounted) return;
      showWalletSnackBar(context, 'Request rejected');
      _load();
    } catch (e) {
      if (!mounted) return;
      showWalletSnackBar(context, 'Reject failed: ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reseller Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: EdgeInsets.all(24.w),
                  child: Text('Failed to load: $_error', textAlign: TextAlign.center)))
              : _agent == null
                  ? Center(child: Padding(
                      padding: EdgeInsets.all(24.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.storefront_outlined, size: 48.w, color: Colors.grey),
                          SizedBox(height: 12.h),
                          const Text('You are not an active reseller.'),
                        ],
                      )))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.all(16.w),
                        children: [
                          Card(
                            child: Padding(
                              padding: EdgeInsets.all(16.w),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('YOUR CODE',
                                            style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                                        SizedBox(height: 4.h),
                                        Row(
                                          children: [
                                            Text(_agent!['reseller_code'] ?? '—',
                                                style: TextStyle(fontSize: 22.sp,
                                                    fontWeight: FontWeight.bold)),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 18),
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(
                                                    text: _agent!['reseller_code'] ?? ''));
                                                showWalletSnackBar(context, 'Code copied');
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('CREDIT BALANCE',
                                          style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                                      SizedBox(height: 4.h),
                                      Text('${_agent!['diamond_credit_balance'] ?? 0} 💎',
                                          style: TextStyle(fontSize: 22.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepPurple)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 16.h),
                          Text('Pending requests (${_pending.length})',
                              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                          if (_pending.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              child: Text('No pending requests right now.',
                                  style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
                            )
                          else
                            ..._pending.map((r) => Card(
                                  margin: EdgeInsets.only(top: 8.h),
                                  child: ListTile(
                                    title: Text(
                                      '${r['profiles']?['display_name'] ?? r['profiles']?['username'] ?? 'User'}'
                                      ' · ${r['diamonds_requested']} 💎',
                                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      '${r['note'] ?? 'No note'}\n'
                                      '${(r['created_at'] ?? '').toString().substring(0, 16).replaceAll("T", " ")}',
                                      style: TextStyle(fontSize: 11.sp),
                                    ),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Approve',
                                          icon: const Icon(Icons.check_circle, color: Colors.green),
                                          onPressed: () => _approve(r['id'] as String),
                                        ),
                                        IconButton(
                                          tooltip: 'Reject',
                                          icon: const Icon(Icons.cancel, color: Colors.red),
                                          onPressed: () => _reject(r['id'] as String),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                          SizedBox(height: 16.h),
                          Text('Credit pool activity',
                              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                          if (_ledger.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              child: Row(children: [
                                Icon(Icons.receipt_long_outlined, size: 32.w, color: Colors.grey),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Text('No movements yet. Recharges you approve will '
                                      'appear here with both sides of the transaction.',
                                      style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                                ),
                              ]),
                            )
                          else
                            ..._ledger.map((l) => ListTile(
                                  dense: true,
                                  leading: Icon(
                                    (l['amount'] as num) >= 0
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    color: (l['amount'] as num) >= 0 ? Colors.green : Colors.red,
                                  ),
                                  title: Text('${l['amount'] >= 0 ? '+' : ''}${l['amount']} '
                                      '${l['currency'] == 'reseller_credit' ? 'credit' : l['currency']}',
                                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                      '${(l['reason'] ?? '').toString().replaceAll('_', ' ')}'
                                      ' · ${(l['created_at'] ?? '').toString().substring(0, 16).replaceAll("T", " ")}',
                                      style: TextStyle(fontSize: 11.sp)),
                                )),
                        ],
                      ),
                    ),
    );
  }
}
