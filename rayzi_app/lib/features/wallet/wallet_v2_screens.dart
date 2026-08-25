import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

/// Shared helpers ----------------------------------------------------------

void showWalletSnackBar(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
    ),
  );
}

String _reasonLabel(String reason) {
  switch (reason) {
    case 'reseller_recharge':
      return 'Recharge';
    case 'admin_grant':
      return 'Admin grant';
    case 'admin_deduction':
      return 'Admin deduction';
    case 'gift_sent':
      return 'Gift sent';
    case 'gift_received':
      return 'Gift received';
    case 'shop_purchase':
      return 'Shop purchase';
    case 'withdraw_request':
      return 'Withdrawal (held)';
    case 'withdraw_reversal':
      return 'Withdrawal reversed';
    default:
      return reason.replaceAll('_', ' ');
  }
}

// ---------------------------------------------------------------------------
// BUY COINS — browse resellers by shareable code + submit a recharge request.
// Balance only changes after an ADMIN approves the request.
// ---------------------------------------------------------------------------
class BuyCoinsScreen extends StatefulWidget {
  const BuyCoinsScreen({super.key});

  @override
  State<BuyCoinsScreen> createState() => _BuyCoinsScreenState();
}

class _BuyCoinsScreenState extends State<BuyCoinsScreen> {
  List<dynamic> _resellers = [];
  bool _loading = true;
  bool _submitting = false;
  String? _selectedCode;
  final _amountController = TextEditingController();
  final _proofController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _proofController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.get('/wallet/resellers');
      if (!mounted) return;
      setState(() {
        _resellers = res.data['data'] ?? [];
        if (_selectedCode == null && _resellers.isNotEmpty) {
          _selectedCode = _resellers.first['reseller_code'] as String?;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showWalletSnackBar(context, 'Failed to load resellers: ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (_selectedCode == null || amount == null || amount <= 0) {
      showWalletSnackBar(context, 'Pick a reseller and enter a valid diamond amount',
          error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/wallet/recharge-by-code', data: {
        'reseller_code': _selectedCode,
        'diamonds_requested': amount,
        'payment_proof_url': _proofController.text.trim(),
        'note': _noteController.text.trim(),
      });
      if (!mounted) return;
      showWalletSnackBar(context, 'Request submitted — waiting for approval');
      _amountController.clear();
      _proofController.clear();
      _noteController.clear();
      setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showWalletSnackBar(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buy Coins')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  Text('Official Resellers',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8.h),
                  if (_resellers.isEmpty)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: Text(
                          'No active resellers right now. Contact support for an admin top-up.',
                          style: TextStyle(fontSize: 13.sp, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ..._resellers.map((r) => RadioListTile<String>(
                          value: r['reseller_code'] as String,
                          groupValue: _selectedCode,
                          onChanged: (v) => setState(() => _selectedCode = v),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  (r['display_name'] ?? r['username'] ?? '') as String,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                                ),
                              ),
                              SizedBox(width: 6.w),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withAlpha((0.15 * 255).round()),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified, size: 12.r,
                                        color: Theme.of(context).colorScheme.primary),
                                    SizedBox(width: 3.w),
                                    Text('Official Reseller',
                                        style: TextStyle(fontSize: 10.sp,
                                            color: Theme.of(context).colorScheme.primary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text('Code: ${r['reseller_code']}'
                              '${r['commission_rate'] != null ? '  ·  fee ${r['commission_rate']}%' : ''}',
                              style: TextStyle(fontSize: 12.sp)),
                        )),
                  SizedBox(height: 16.h),
                  Text('Request recharge',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Diamonds requested',
                      hintText: 'e.g. 500',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                      prefixIcon: const Icon(Icons.diamond_outlined),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: _proofController,
                    decoration: InputDecoration(
                      labelText: 'Payment proof URL (optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                    child: _submitting
                        ? SizedBox(width: 20.r, height: 20.r,
                            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Submit Request', style: TextStyle(fontSize: 15.sp)),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Your diamonds are credited only after an admin approves the '
                    'request. Track progress in My Recharge Requests.',
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// WITHDRAW — hold-on-submit / reversal-on-reject flow with status tracking.
// Payout is sent manually by the operator; "paid" is recorded afterwards.
// ---------------------------------------------------------------------------
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  List<dynamic> _requests = [];
  bool _loading = true;
  bool _submitting = false;
  int? _balance;
  final _amountController = TextEditingController();
  final _accountController = TextEditingController();
  final _nameController = TextEditingController();
  String _method = 'bkash';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _accountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.get('/wallet/withdrawals'),
        ApiService.get('/wallet/balance'),
      ]);
      if (!mounted) return;
      setState(() {
        _requests = results[0].data['data'] ?? [];
        _balance = results[1].data['data']?['diamonds'] as int?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showWalletSnackBar(context, 'Failed to load withdrawals: ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showWalletSnackBar(context, 'Enter a valid diamond amount', error: true);
      return;
    }
    if (_accountController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty) {
      showWalletSnackBar(context, 'Account number and name are required', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService.post('/wallet/withdrawals', data: {
        'diamonds_requested': amount,
        'payout_method': _method,
        'payout_details': {
          'account_number': _accountController.text.trim(),
          'account_name': _nameController.text.trim(),
        },
      });
      if (!mounted) return;
      showWalletSnackBar(context, 'Submitted — diamonds held until review');
      _amountController.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showWalletSnackBar(context, friendlyError(e), error: true);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'approved':
        return Colors.teal;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.all(16.w),
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(14.w),
                      child: Row(
                        children: [
                          Icon(Icons.diamond, color: Colors.cyan, size: 26.w),
                          SizedBox(width: 10.w),
                          Text('Spendable diamonds: ',
                              style: TextStyle(fontSize: 13.sp)),
                          Text('${_balance ?? 0}',
                              style: TextStyle(
                                  fontSize: 16.sp, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Diamonds to withdraw',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                      prefixIcon: const Icon(Icons.diamond_outlined),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  DropdownButtonFormField<String>(
                    value: _method,
                    items: const [
                      DropdownMenuItem(value: 'bkash', child: Text('bKash')),
                      DropdownMenuItem(value: 'nagad', child: Text('Nagad')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? 'bkash'),
                    decoration: InputDecoration(
                      labelText: 'Payout method',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: _accountController,
                    decoration: InputDecoration(
                      labelText: 'Account number',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                      prefixIcon: const Icon(Icons.numbers),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Account holder name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                    child: _submitting
                        ? SizedBox(width: 20.r, height: 20.r,
                            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('Submit Withdrawal', style: TextStyle(fontSize: 15.sp)),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Requested diamonds are held immediately and returned '
                    'automatically if an admin rejects the request.',
                    style: TextStyle(fontSize: 11.sp, color: Colors.grey),
                  ),
                  SizedBox(height: 16.h),
                  Text('My Withdrawals',
                      style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  if (_requests.isEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.h),
                      child: Center(
                        child: Text('No withdrawal requests yet',
                            style: TextStyle(fontSize: 13.sp, color: Colors.grey)),
                      ),
                    )
                  else
                    ..._requests.map((w) {
                      final payout = w['payout_amount'];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.payments_outlined,
                            color: _statusColor(w['status'] as String? ?? 'pending')),
                        title: Text('${w['diamonds_requested']} 💎'
                            '${payout != null ? '  →  $payout' : ''}',
                            style: TextStyle(fontSize: 14.sp)),
                        subtitle: Text(
                          '${w['payout_method']} · ${DateFormat('MMM d, HH:mm').format(DateTime.parse(w['created_at']))}'
                          '${w['rejection_reason'] != null ? '\nReason: ${w['rejection_reason']}' : ''}',
                          style: TextStyle(fontSize: 11.sp),
                        ),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: _statusColor(w['status'] as String? ?? 'pending').withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text((w['status'] as String? ?? '').toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w700,
                                  color: _statusColor(w['status'] as String? ?? 'pending'))),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// WALLET LEDGER — audit view of every balance movement on this account.
// ---------------------------------------------------------------------------
class WalletLedgerScreen extends StatefulWidget {
  const WalletLedgerScreen({super.key});

  @override
  State<WalletLedgerScreen> createState() => _WalletLedgerScreenState();
}

class _WalletLedgerScreenState extends State<WalletLedgerScreen> {
  List<dynamic> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.get('/wallet/ledger',
          queryParameters: {'limit': 100});
      if (!mounted) return;
      final data = res.data['data'] ?? [];
      _rows = data is List ? data : [];
      _loading = false;
    } catch (e) {
      if (!mounted) return;
      _rows = [];
      _loading = false;
      showWalletSnackBar(context, 'Failed to load ledger: ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet Ledger')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 96.h),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 48.r, color: Colors.grey),
                            SizedBox(height: 12.h),
                            Text('No movements yet',
                                style: TextStyle(
                                    fontSize: 14.sp, color: Colors.grey)),
                            SizedBox(height: 4.h),
                            Text('Recharges, gifts, purchases and withdrawals '
                                'will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11.sp, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ])
                  : ListView.separated(
                padding: EdgeInsets.all(16.w),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1, color: Theme.of(context).dividerColor),
                itemBuilder: (context, i) {
                  final row = _rows[i] as Map<String, dynamic>;
                  final amount = (row['amount'] as num? ?? 0).toInt();
                  final credit = amount >= 0;
                  final currency = row['currency'] as String? ?? '';
                  final symbol = currency == 'coins' ? '🪙' : currency == 'diamonds' ? '💎' : '💠';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(credit ? Icons.arrow_downward : Icons.arrow_upward,
                        color: credit ? Colors.green : Colors.red),
                    title: Text(_reasonLabel(row['reason'] as String? ?? 'other'),
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((row['note'] as String?)?.isNotEmpty == true)
                          Text(row['note'], style: TextStyle(fontSize: 11.sp), maxLines: 2),
                        Text(
                          DateFormat('MMM d, yyyy HH:mm')
                              .format(DateTime.parse(row['created_at'] as String)),
                          style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: RichText(
                      textAlign: TextAlign.end,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(
                            text: '${credit ? '+' : ''}$amount',
                            style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: credit ? Colors.green : Colors.red),
                          ),
                          TextSpan(text: ' $symbol\n'),
                          TextSpan(
                            text: 'bal ${(row['balance_after'] as num? ?? 0)}',
                            style: TextStyle(fontSize: 10.sp, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
