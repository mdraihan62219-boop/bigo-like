import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';

class WithdrawalsScreen extends StatefulWidget {
  const WithdrawalsScreen({super.key});

  @override
  State<WithdrawalsScreen> createState() => _WithdrawalsScreenState();
}

class _WithdrawalsScreenState extends State<WithdrawalsScreen> {
  List<dynamic> _withdrawals = [];
  bool _isLoading = true;
  String? _error;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.get('/admin/withdrawals', query: {'status': _status, 'limit': 100});
      setState(() {
        _withdrawals = (data as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _process(String id, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action == 'approve' ? 'Approve withdrawal?' : 'Reject withdrawal?'),
        content: Text(
          action == 'approve'
            ? 'Mark this payout as completed?'
            : 'Rejecting refunds the diamonds to the user automatically.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AdminApi.post('/admin/withdrawals/$id/$action');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Withdrawal ${action == 'approve' ? 'approved' : 'rejected'}')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdrawals'),
        actions: [
          DropdownButton<String>(
            value: _status,
            underline: const SizedBox(),
            items: ['pending', 'completed', 'failed']
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
            onChanged: (v) { _status = v ?? 'pending'; _load(); },
          ),
          const SizedBox(width: 16),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Failed to load withdrawals'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ))
          : _withdrawals.isEmpty
            ? const Center(child: Text('No withdrawals with this status'))
            : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _withdrawals.length,
            itemBuilder: (context, index) {
              final w = _withdrawals[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    w['status'] == 'pending' ? Icons.hourglass_top : Icons.check_circle,
                    color: w['status'] == 'pending' ? Colors.orange : Colors.green,
                  ),
                  title: Text('${w['profiles']?['display_name'] ?? 'Unknown'} — ${w['amount']} diamonds'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w['description'] ?? ''),
                      Text(DateFormat('MMM d, yyyy HH:mm')
                        .format(DateTime.parse(w['created_at']))),
                    ],
                  ),
                  trailing: w['status'] == 'pending'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _process(w['id'], 'reject'),
                            child: const Text('Reject', style: TextStyle(color: Colors.red)),
                          ),
                          ElevatedButton(
                            onPressed: () => _process(w['id'], 'approve'),
                            child: const Text('Approve'),
                          ),
                        ],
                      )
                    : Chip(label: Text(w['status'] ?? '')),
                ),
              );
            },
          ),
    );
  }
}
