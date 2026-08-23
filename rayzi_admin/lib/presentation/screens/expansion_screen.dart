import 'package:flutter/material.dart';
import '../../services/admin_api.dart';

/// v2 expansion admin: Shop items CRUD, Reseller recharge approvals +
/// agents, Host application review queue.
class ExpansionScreen extends StatefulWidget {
  const ExpansionScreen({super.key});

  @override
  State<ExpansionScreen> createState() => _ExpansionScreenState();
}

class _ExpansionScreenState extends State<ExpansionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  List<dynamic> _shopItems = [];
  List<dynamic> _requests = [];
  List<dynamic> _hostApps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AdminApi.get('/admin/shop/items'),
        AdminApi.get('/admin/reseller/requests'),
        AdminApi.get('/admin/host-applications'),
      ]);
      if (!mounted) return;
      setState(() {
        _shopItems = results[0]['data'] ?? [];
        _requests = results[1]['data'] ?? [];
        _hostApps = results[2]['data'] ?? [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expansion Management'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Shop Items'),
          Tab(text: 'Recharge Requests'),
          Tab(text: 'Host Applications'),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildShop(),
                _buildRequests(),
                _buildHostApps(),
              ],
            ),
    );
  }

  // ---------------- Shop ----------------
  Widget _buildShop() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _createShopItem,
            icon: const Icon(Icons.add),
            label: const Text('New Item'),
          ),
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: _shopItems.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final item = _shopItems[i] as Map<String, dynamic>;
            final active = item['is_active'] == true;
            return ListTile(
              leading: Icon(Icons.card_giftcard,
                  color: item['tier'] == 'king' ? Colors.amber : null),
              title: Text('${item['name']} (${item['category']}'
                  '${item['tier'] != null ? ' · ${item['tier']}' : ''})'),
              subtitle: Text('💎 ${item['price_diamonds']}'
                  ' · ${item['duration_days'] == null ? 'permanent' : '${item['duration_days']}d'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Switch(value: active, onChanged: (_) => _toggleItem(item, !active)),
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteItem(item)),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Future<void> _createShopItem() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final category = TextEditingController(text: 'badge');
    final tier = TextEditingController(text: 'vip');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Shop Item'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
          TextField(controller: tier, decoration: const InputDecoration(labelText: 'Tier (optional)')),
          TextField(controller: price, decoration: const InputDecoration(labelText: 'Price (diamonds)'),
              keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await AdminApi.post('/admin/shop/items', data: {
        'name': name.text.trim(),
        'category': category.text.trim(),
        'tier': tier.text.trim().isEmpty ? null : tier.text.trim(),
        'price_diamonds': int.tryParse(price.text.trim()) ?? 0,
      });
      _load();
    } catch (e) {
      _snack('Create failed: $e');
    }
  }

  Future<void> _toggleItem(Map<String, dynamic> item, bool active) async {
    try {
      await AdminApi.put('/admin/shop/items/${item['id']}', data: {'is_active': active});
      _load();
    } catch (e) {
      _snack('Update failed: $e');
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    try {
      await AdminApi.delete('/admin/shop/items/${item['id']}');
      _load();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  // ---------------- Reseller requests ----------------
  Widget _buildRequests() {
    if (_requests.isEmpty) return const Center(child: Text('No recharge requests'));
    return ListView.separated(
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _requests[i] as Map<String, dynamic>;
        final pending = r['status'] == 'pending';
        return ListTile(
          leading: Icon(Icons.diamond,
              color: pending ? Colors.orange : (r['status'] == 'approved' ? Colors.green : Colors.red)),
          title: Text('${r['diamonds_requested']} diamonds — ${r['status']}'),
          subtitle: Text('from user ${r['requester_id'].toString().substring(0, 8)}…'
              '${r['payment_proof_url'] != null ? ' · proof attached' : ''}'),
          trailing: pending
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve', onPressed: () => _decide(r, true)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Reject', onPressed: () => _decide(r, false)),
                ])
              : null,
        );
      },
    );
  }

  Future<void> _decide(Map<String, dynamic> request, bool approve) async {
    try {
      final path = approve ? 'approve' : 'reject';
      await AdminApi.post('/admin/reseller/requests/${request['id']}/$path',
          data: approve ? null : {'reason': 'Rejected by admin'});
      _snack(approve ? 'Approved — diamonds credited' : 'Rejected');
      _load();
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  // ---------------- Host applications ----------------
  Widget _buildHostApps() {
    if (_hostApps.isEmpty) return const Center(child: Text('No host applications'));
    return ListView.separated(
      itemCount: _hostApps.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final a = _hostApps[i] as Map<String, dynamic>;
        final profile = a['profiles'] as Map<String, dynamic>? ?? {};
        final pending = a['status'] == 'pending';
        return ListTile(
          leading: const Icon(Icons.live_tv),
          title: Text('${a['full_name']} (@${profile['username'] ?? '?'})'),
          subtitle: Text('phone: ${a['phone_number']} · ${a['status']}'),
          trailing: pending
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve', onPressed: () => _hostDecide(a, true)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: 'Reject', onPressed: () => _hostDecide(a, false)),
                ])
              : Chip(label: Text(a['status'] ?? '')),
        );
      },
    );
  }

  Future<void> _hostDecide(Map<String, dynamic> app, bool approve) async {
    try {
      final path = approve ? 'approve' : 'reject';
      await AdminApi.post('/admin/host-applications/${app['id']}/$path',
          data: approve ? null : {'reason': 'Does not meet requirements'});
      _snack(approve ? 'Host approved' : 'Application rejected');
      _load();
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
