import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api.dart';

/// Wallet Ledger / Adjustments + Withdraw queue + Reseller directory.
///
/// Every balance change shown here was written by an atomic server-side RPC
/// that stamps the acting admin/reseller/user on the ledger row, so this
/// screen doubles as the financial audit view.
class WalletEconomyScreen extends StatefulWidget {
  const WalletEconomyScreen({super.key});

  @override
  State<WalletEconomyScreen> createState() => _WalletEconomyScreenState();
}

class _WalletEconomyScreenState extends State<WalletEconomyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  // Ledger tab state
  List<dynamic> _ledger = [];
  String? _filterUserId;
  String? _filterAdminCode;

  // Withdraw queue state
  List<dynamic> _withdrawals = [];

  // Resellers state
  List<dynamic> _resellers = [];

  bool _loading = true;
  final _userSearch = TextEditingController();
  final _adminCodeSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await Future.wait([_loadLedger(), _loadWithdrawals(), _loadResellers()]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _ledgerQuery() {
    final q = <String, dynamic>{'limit': 100};
    if (_filterUserId != null && _filterUserId!.isNotEmpty) q['user_id'] = _filterUserId;
    if (_filterAdminCode != null && _filterAdminCode!.isNotEmpty) q['admin_code'] = _filterAdminCode;
    return q;
  }

  Future<void> _loadLedger() async {
    try {
      final res = await AdminApi.get('/admin/wallet/ledger', query: _ledgerQuery());
      if (!mounted) return;
      setState(() {
        _ledger = res is List ? res : (res?['data'] ?? []);
        if (_filterAdminCode != null && _filterAdminCode!.isEmpty) _filterAdminCode = null;
      });
    } catch (_) {}
  }

  Future<void> _loadWithdrawals() async {
    try {
      final res = await AdminApi.get('/admin/wallet/withdrawals');
      if (!mounted) return;
      setState(() => _withdrawals = res is List ? res : []);
    } catch (_) {}
  }

  Future<void> _loadResellers() async {
    try {
      final res = await AdminApi.get('/admin/reseller/agents');
      if (!mounted) return;
      setState(() => _resellers = res is List ? res : []);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wallet Economy'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Ledger / Adjust'),
            Tab(text: 'Withdraw Queue'),
            Tab(text: 'Resellers'),
          ]),
        ),
        floatingActionButton: _tabs.index == 0
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.tune),
                label: const Text('Adjust Balance'),
                onPressed: _adjustDialog,
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAll,
                child: TabBarView(
                  controller: _tabs,
                  children: [_buildLedger(), _buildWithdrawals(), _buildResellers()],
                ),
              ),
      ),
    );
  }

  // ---------------- Ledger ----------------
  Widget _buildLedger() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _userSearch,
              decoration: const InputDecoration(
                labelText: 'User ID filter',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _adminCodeSearch,
              decoration: const InputDecoration(
                labelText: 'Admin code (e.g. ADM-014)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              _filterUserId = _userSearch.text.trim();
              _filterAdminCode = _adminCodeSearch.text.trim().toUpperCase();
              _loadLedger();
              setState(() {});
            },
            child: const Text('Filter'),
          ),
        ]),
      ),
      Expanded(
        child: _ledger.isEmpty
            ? ListView(children: const [
                Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No ledger entries'))),
              ])
            : ListView.separated(
                itemCount: _ledger.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final row = _ledger[i] as Map<String, dynamic>;
                  final amount = (row['amount'] as num? ?? 0).toInt();
                  final credit = amount >= 0;
                  final actor = row['actor'] as Map<String, dynamic>?;
                  return ListTile(
                    leading: Icon(credit ? Icons.south : Icons.north,
                        color: credit ? Colors.green : Colors.red),
                    title: Text('${row['reason'] ?? '?'} · ${row['currency']}'),
                    subtitle: Text(
                      '${credit ? '+' : ''}$amount → balance ${row['balance_after']}'
                      '\nactor: ${actor?['username'] ?? 'system'}'
                      '${actor?['admin_code'] != null ? ' (${actor!['admin_code']})' : ''}'
                      '${row['note'] != null ? '\n${row['note']}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(DateFormat('MMM d\nHH:mm')
                        .format(DateTime.parse(row['created_at'] as String))),
                    isThreeLine: true,
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _adjustDialog() async {
    final user = TextEditingController();
    final amount = TextEditingController();
    final note = TextEditingController();
    var currency = 'coins';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adjust Balance'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Every adjustment is stamped with your admin code in the ledger.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: user,
                decoration: const InputDecoration(labelText: 'Target user ID')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: currency,
              items: const [
                DropdownMenuItem(value: 'coins', child: Text('Coins')),
                DropdownMenuItem(value: 'diamonds', child: Text('Diamonds')),
              ],
              onChanged: (v) => setDialogState(() => currency = v ?? 'coins'),
              decoration: const InputDecoration(labelText: 'Currency'),
            ),
            TextField(controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Amount (+grant / −deduction)',
                    helperText: 'Negative values deduct; balance cannot go below zero')),
            const SizedBox(height: 8),
            TextField(controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason / note (required)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = BigInt.tryParse(amount.text.trim()) ?? BigInt.zero;
    if (user.text.trim().isEmpty || amt == BigInt.zero || note.text.trim().length < 3) {
      _snack('User id, non-zero amount and a note are required');
      return;
    }
    try {
      await AdminApi.post('/admin/wallet/adjust', data: {
        'user_id': user.text.trim(),
        'currency': currency,
        'amount': amt.toInt(),
        'note': note.text.trim(),
      });
      _snack('Balance adjusted and logged');
      await _loadLedger();
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Adjust failed: $e');
    }
  }

  // ---------------- Withdraw queue ----------------
  Widget _buildWithdrawals() {
    if (_withdrawals.isEmpty) {
      return ListView(children: const [
        Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No withdrawal requests'))),
      ]);
    }
    return ListView.separated(
      itemCount: _withdrawals.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final w = _withdrawals[i] as Map<String, dynamic>;
        final profile = w['profiles'] as Map<String, dynamic>? ?? {};
        final details = w['payout_details'] as Map<String, dynamic>? ?? {};
        final status = w['status'] as String? ?? 'pending';
        final actionable = status == 'pending' || status == 'approved';
        return ListTile(
          leading: Icon(Icons.payments,
              color: status == 'paid'
                  ? Colors.green
                  : status == 'rejected'
                      ? Colors.red
                      : Colors.orange),
          title: Text(
              '${w['diamonds_requested']} 💎 → ${w['payout_amount'] ?? '?'} '
              '(${w['payout_method']}) — $status'),
          subtitle: Text(
            '@${profile['username'] ?? '?'} · ${details['account_name'] ?? ''} '
            '${details['account_number'] ?? ''}\n'
            '${DateFormat('MMM d, HH:mm').format(DateTime.parse(w['created_at'] as String))}',
            style: const TextStyle(fontSize: 12),
          ),
          isThreeLine: true,
          trailing: actionable
              ? PopupMenuButton<String>(
                  onSelected: (action) => _withdrawAction(w, action),
                  itemBuilder: (_) => [
                    if (status == 'pending') const PopupMenuItem(value: 'approve', child: Text('Approve')),
                    const PopupMenuItem(value: 'paid', child: Text('Mark paid (money sent)')),
                    const PopupMenuItem(value: 'reject', child: Text('Reject & reverse hold')),
                  ],
                )
              : Chip(label: Text(status)),
        );
      },
    );
  }

  Future<void> _withdrawAction(Map<String, dynamic> w, String action) async {
    var reason = '';
    if (action == 'reject') {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject & reverse'),
          content: TextField(controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason shown to the user')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
      reason = controller.text.trim();
      if (reason.isEmpty) {
        _snack('A rejection reason is required');
        return;
      }
    }
    try {
      await AdminApi.post('/admin/wallet/withdrawals/${w['id']}/$action',
          data: action == 'reject' ? {'reason': reason} : null);
      _snack(action == 'paid'
          ? 'Marked paid — record kept in ledger'
          : 'Withdrawal $action');
      await _loadAll();
      if (mounted) setState(() {});
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  // ---------------- Resellers ----------------
  Widget _buildResellers() {
    if (_resellers.isEmpty) {
      return ListView(children: const [
        Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No reseller agents'))),
      ]);
    }
    return ListView.separated(
      itemCount: _resellers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _resellers[i] as Map<String, dynamic>;
        final profile = r['profiles'] as Map<String, dynamic>? ?? {};
        return ListTile(
          leading: Icon(Icons.store,
              color: r['is_active'] == true ? Colors.green : Colors.grey),
          title: Text('@${profile['username'] ?? '?'} · ${r['reseller_code'] ?? '—'}'),
          subtitle: Text(
            'credit: ${r['diamond_credit_balance']} 💎 · commission ${r['commission_rate']}%'
            '${r['is_active'] == true ? '' : ' · INACTIVE'}',
          ),
        );
      },
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
