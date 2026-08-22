import 'package:flutter/material.dart';
import '../../services/admin_api.dart';
import '../widgets/admin_drawer.dart';

class GiftsScreen extends StatefulWidget {
  const GiftsScreen({super.key});

  @override
  State<GiftsScreen> createState() => _GiftsScreenState();
}

class _GiftsScreenState extends State<GiftsScreen> {
  List<dynamic> _gifts = [];
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
      final data = await AdminApi.get('/admin/gifts');
      setState(() {
        _gifts = (data as List?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> gift) async {
    try {
      await AdminApi.put('/admin/gifts/${gift['id']}', data: {
        'is_active': !(gift['is_active'] == true),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  void _showCreateDialog() {
    final name = TextEditingController();
    final price = TextEditingController();
    final diamonds = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Gift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: price, decoration: const InputDecoration(labelText: 'Price (coins)'), keyboardType: TextInputType.number),
            TextField(controller: diamonds, decoration: const InputDecoration(labelText: 'Diamond value'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await AdminApi.post('/admin/gifts', data: {
                  'name': name.text.trim(),
                  'price_coins': int.tryParse(price.text) ?? 0,
                  'diamond_value': int.tryParse(diamonds.text) ?? 0,
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _load();
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text('Create failed: $e')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gifts'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Create gift', onPressed: _showCreateDialog),
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
                Text('Failed to load gifts'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ))
          : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, childAspectRatio: 0.9,
            ),
            itemCount: _gifts.length,
            itemBuilder: (context, index) {
              final gift = _gifts[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(gift['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${gift['price_coins']} coins'),
                      Text('${gift['diamond_value']} diamonds',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      SwitchListTile(
                        dense: true,
                        title: const Text('Active'),
                        value: gift['is_active'] == true,
                        onChanged: (_) => _toggleActive(Map<String, dynamic>.from(gift as Map)),
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
