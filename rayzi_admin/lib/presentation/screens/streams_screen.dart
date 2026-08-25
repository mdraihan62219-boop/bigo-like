import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';

class StreamsScreen extends StatefulWidget {
  const StreamsScreen({super.key});

  @override
  State<StreamsScreen> createState() => _StreamsScreenState();
}

class _StreamsScreenState extends State<StreamsScreen> {
  List<dynamic> _streams = [];
  bool _isLoading = true;
  String? _error;

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
      final data = await AdminApi.get('/admin/streams', query: {'limit': 100});
      setState(() {
        _streams = (data as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _banStream(String id) async {
    try {
      await AdminApi.post('/admin/streams/$id/ban');
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ban failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streams'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Failed to load streams'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ))
          : Padding(
            padding: const EdgeInsets.all(16),
            child: DataTable2(
              columnSpacing: 12,
              minWidth: 800,
              columns: const [
                DataColumn2(label: Text('Title'), size: ColumnSize.L),
                DataColumn2(label: Text('Host')),
                DataColumn2(label: Text('Status')),
                DataColumn2(label: Text('Viewers')),
                DataColumn2(label: Text('Likes')),
                DataColumn2(label: Text('Actions')),
              ],
              rows: _streams.map((s) {
                return DataRow(cells: [
                  DataCell(Text(s['title'] ?? '')),
                  DataCell(Text(s['profiles']?['display_name'] ?? 'Unknown')),
                  DataCell(Chip(label: Text(s['status'] ?? ''))),
                  DataCell(Text('${s['current_viewers'] ?? 0}')),
                  DataCell(Text('${s['likes'] ?? 0}')),
                  DataCell(
                    (s['status'] == 'live')
                      ? IconButton(icon: const Icon(Icons.block, color: Colors.red), tooltip: 'Ban stream', onPressed: () => _banStream(s['id']))
                      : const SizedBox(),
                  ),
                ]);
              }).toList(),
            ),
          ),
    );
  }
}
