import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

/// Grid of owned entry animations with a looping scale/fade preview.
class EntryAnimationSelectorScreen extends StatefulWidget {
  const EntryAnimationSelectorScreen({super.key});

  @override
  State<EntryAnimationSelectorScreen> createState() =>
      _EntryAnimationSelectorScreenState();
}

class _EntryAnimationSelectorScreenState
    extends State<EntryAnimationSelectorScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _owned = [];
  String? _currentId;
  bool _isLoading = true;
  late final AnimationController _preview = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService.get('/inventory'),
        ApiService.get('/profile/summary'),
      ]);
      if (!mounted) return;
      setState(() {
        final all = results[0].data['data'] ?? [];
        _owned = all.where((i) => i['shop_items']?['category'] == 'entry_animation').toList();
        _currentId = results[1].data['data']?['equipped_entry_animation_id'];
        _isLoading = _owned.isEmpty ? false : false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load entry animations: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> inv) async {
    try {
      await ApiService.put('/profile/entry-animation', data: {'item_id': inv['item_id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${inv['shop_items']?['name']} equipped')));
      _preview.forward(from: 0);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entry Animations')),
body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _owned.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 48.r, color: Colors.grey),
                        SizedBox(height: 12.h),
                        Text('No entry animations owned',
                            style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
                        SizedBox(height: 4.h),
                        Text('Earn animations from shop packs.',
                            style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                      ],
                    ),
                  )
                : GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12.w, mainAxisSpacing: 12.h,
                childAspectRatio: 1.1,
              ),
              itemCount: _owned.length,
              itemBuilder: (context, index) {
                final inv = _owned[index] as Map<String, dynamic>;
                final item = (inv['shop_items'] as Map<String, dynamic>?) ?? {};
                return Card(
                  child: InkWell(
                    onTap: () => _apply(inv),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      ScaleTransition(
                        scale: CurvedAnimation(parent: _preview, curve: Curves.elasticOut),
                        child: FadeTransition(
                          opacity: _preview,
                          child: const Icon(Icons.auto_awesome),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(item['name'] ?? '', style: TextStyle(fontSize: 13.sp)),
                      if (_currentId == inv['item_id'])
                        Chip(label: Text('Equipped', style: TextStyle(fontSize: 10.sp))),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
