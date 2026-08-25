import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  final int _rowsPerPage = 25;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await AdminApi.get('/admin/users', query: {
        'page': _page,
        'limit': _rowsPerPage,
      });
      setState(() {
        _users = (data as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _banUser(String userId, String reason) async {
    try {
      await AdminApi.post('/admin/users/$userId/ban', data: {'reason': reason});
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ban failed: $e')));
      }
    }
  }

  Future<void> _unbanUser(String userId) async {
    try {
      await AdminApi.post('/admin/users/$userId/unban');
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Unban failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Management — page $_page'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1 ? () { setState(() => _page--); _loadUsers(); } : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () { setState(() => _page++); _loadUsers(); },
          ),
        ],
      ),
      drawer: const AdminDrawer(),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Failed to load users'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _loadUsers, child: const Text('Retry')),
              ],
            ))
          : Padding(
            padding: const EdgeInsets.all(16),
            child: DataTable2(
              columnSpacing: 12,
              horizontalMargin: 12,
              minWidth: 800,
              columns: const [
                DataColumn2(label: Text('User'), size: ColumnSize.L),
                DataColumn2(label: Text('Status')),
                DataColumn2(label: Text('Coins')),
                DataColumn2(label: Text('Diamonds')),
                DataColumn2(label: Text('Joined')),
                DataColumn2(label: Text('Actions'), size: ColumnSize.S),
              ],
              rows: _users.map((user) {
                return DataRow(
                  cells: [
                    DataCell(Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: (user['avatar_url'] ?? '').toString().isNotEmpty
                            ? NetworkImage(user['avatar_url'])
                            : null,
                          radius: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(user['display_name'] ?? user['username'] ?? 'Unknown')),
                      ],
                    )),
                    DataCell(
                      user['is_banned'] == true
                        ? Chip(label: const Text('Banned'), backgroundColor: Colors.red[100])
                        : Chip(label: const Text('Active'), backgroundColor: Colors.green[100]),
                    ),
                    DataCell(Text('${user['coins'] ?? 0}')),
                    DataCell(Text('${user['diamonds'] ?? 0}')),
                    DataCell(Text(user['created_at']?.toString().split('T')[0] ?? 'N/A')),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user['role'] != 'admin')
                          (user['is_banned'] != true)
                            ? IconButton(
                                icon: const Icon(Icons.block, color: Colors.red),
                                tooltip: 'Ban',
                                onPressed: () => _showBanDialog(user['id']),
                              )
                            : IconButton(
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                tooltip: 'Unban',
                                onPressed: () => _unbanUser(user['id']),
                              ),
                      ],
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
    );
  }

  void _showBanDialog(String userId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ban User'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _banUser(userId, controller.text);
            },
            child: const Text('Ban'),
          ),
        ],
      ),
    );
  }
}
