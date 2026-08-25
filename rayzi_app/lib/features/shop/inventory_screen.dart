import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';
import '../../utils/api_error.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.get('/inventory');
      if (!mounted) return;
      setState(() {
        _items = response.data['data'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleEquip(Map<String, dynamic> inv) async {
    final equip = inv['is_equipped'] != true;
    try {
      await ApiService.post('/inventory/${inv['id']}/equip');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(equip ? 'Equipped' : 'Unequipped')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: ${friendlyError(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Items')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No items yet — visit the Shop!')),
                    ])
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final inv = _items[index] as Map<String, dynamic>;
                        final item = inv['shop_items'] as Map<String, dynamic>? ?? {};
                        final equipped = inv['is_equipped'] == true;
                        return ListTile(
                          leading: Icon(Icons.card_giftcard, size: 26.r),
                          title: Text(item['name'] ?? 'Item',
                              style: TextStyle(fontSize: 14.sp)),
                          subtitle: Text('${item['category'] ?? ''} · '
                              '${inv['expires_at'] == null ? 'Permanent' : 'Expires ${inv['expires_at']}'}',
                              style: TextStyle(fontSize: 11.sp)),
                          trailing: FilledButton.tonal(
                            onPressed: () => _toggleEquip(inv),
                            child: Text(equipped ? 'Equipped ✓' : 'Equip',
                                style: TextStyle(fontSize: 12.sp)),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
