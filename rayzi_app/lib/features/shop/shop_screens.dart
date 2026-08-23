import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

class ShopHomeScreen extends StatelessWidget {
  const ShopHomeScreen({super.key});

  static const _rows = [
    {'tier': 'king', 'title': 'KING', 'subtitle': 'Royal badges & frames', 'icon': Icons.workspace_premium, 'color': Color(0xFFF5C518)},
    {'tier': 'crown', 'title': 'CROWN', 'subtitle': 'Silver tier items', 'icon': Icons.military_tech, 'color': Color(0xFFC0C0C0)},
    {'tier': 'vvip', 'title': 'VVIP', 'subtitle': 'Ultra-premium memberships', 'icon': Icons.diamond, 'color': Color(0xFFFF6B9D)},
    {'tier': 'vip', 'title': 'VIP', 'subtitle': 'Classic VIP perks', 'icon': Icons.star, 'color': Color(0xFF00D4FF)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          for (final row in _rows)
            Card(
              margin: EdgeInsets.only(bottom: 12.h),
              child: ListTile(
                leading: Icon(row['icon'] as IconData, color: row['color'] as Color, size: 30.r),
                title: Text(row['title'] as String,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
                subtitle: Text(row['subtitle'] as String, style: TextStyle(fontSize: 12.sp)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, '/shop-tier', arguments: row['tier']),
              ),
            ),
          Card(
            margin: EdgeInsets.only(bottom: 12.h),
            child: ListTile(
              leading: Icon(Icons.receipt_long, color: Colors.greenAccent, size: 30.r),
              title: Text('Recharge from Reseller',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
              subtitle: Text('Pay via agent, get diamonds approved', style: TextStyle(fontSize: 12.sp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/reseller-recharge'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.live_tv, color: Colors.orangeAccent, size: 30.r),
              title: Text('Host Request',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp)),
              subtitle: Text('Apply to become an official host', style: TextStyle(fontSize: 12.sp)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/host-request'),
            ),
          ),
        ],
      ),
    );
  }
}

class ShopTierScreen extends StatefulWidget {
  const ShopTierScreen({super.key, required this.tier});
  final String tier;

  @override
  State<ShopTierScreen> createState() => _ShopTierScreenState();
}

class _ShopTierScreenState extends State<ShopTierScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  bool _purchasingId = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      // Tier spans badges/frames/vip_tier — fetch all and filter client-side.
      final response = await ApiService.get('/shop/items');
      final all = (response.data['data'] ?? []) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _items = all.where((i) => i['tier'] == widget.tier).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _buy(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Buy ${item['name']}?'),
        content: Text('This will cost ${item['price_diamonds']} diamonds.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buy')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _purchasingId = true);
    try {
      await ApiService.post('/shop/purchase', data: {'item_id': item['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Purchased! Check My Items to equip.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Purchase failed: $e')));
    } finally {
      if (mounted) setState(() => _purchasingId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.tier.toUpperCase()} Shop')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12.w,
                mainAxisSpacing: 12.h,
                childAspectRatio: 0.85,
              ),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index] as Map<String, dynamic>;
                return Card(
                  child: Padding(
                    padding: EdgeInsets.all(10.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: Icon(_iconFor(item['category'] as String?),
                                size: 44.r, color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        Text(item['name'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4.h),
                        Text(item['duration_days'] == null
                            ? 'Permanent'
                            : '${item['duration_days']} days',
                            style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                        SizedBox(height: 6.h),
                        FilledButton(
                          onPressed: _purchasingId ? null : () => _buy(item),
                          child: Text('💎 ${item['price_diamonds']}', style: TextStyle(fontSize: 12.sp)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _iconFor(String? category) {
    switch (category) {
      case 'badge':
        return Icons.badge;
      case 'avatar_frame':
        return Icons.circle_outlined;
      case 'vip_tier':
        return Icons.workspace_premium;
      case 'theme':
        return Icons.palette;
      case 'entry_animation':
        return Icons.animation;
      case 'name_effect':
        return Icons.text_fields;
      default:
        return Icons.card_giftcard;
    }
  }
}
