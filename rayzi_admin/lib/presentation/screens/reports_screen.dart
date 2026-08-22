import 'package:flutter/material.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<dynamic> _reports = [];
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
      final data = await AdminApi.get('/admin/reports', query: {'status': _status, 'limit': 100});
      setState(() {
        _reports = (data as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _resolve(String id, String status) async {
    try {
      await AdminApi.post('/admin/reports/$id/resolve', data: {'status': status});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          DropdownButton<String>(
            value: _status,
            underline: const SizedBox(),
            items: ['pending', 'reviewing', 'resolved', 'dismissed']
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
            onChanged: (v) { _status = v ?? 'pending'; _load(); },
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Failed to load reports'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ))
          : _reports.isEmpty
            ? const Center(child: Text('No reports with this status'))
            : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reports.length,
              itemBuilder: (context, index) {
                final r = _reports[index];
                final resolved = r['status'] == 'resolved' || r['status'] == 'dismissed';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.report, color: Colors.orange),
                    title: Text(r['reason'] ?? ''),
                    subtitle: Text(r['description'] ?? ''),
                    trailing: resolved
                      ? Chip(label: Text(r['status'] ?? ''))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _resolve(r['id'], 'dismissed'),
                              child: const Text('Dismiss'),
                            ),
                            ElevatedButton(
                              onPressed: () => _resolve(r['id'], 'resolved'),
                              child: const Text('Resolve'),
                            ),
                          ],
                        ),
                  ),
                );
              },
            ),
    );
  }
}
