import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

/// Grid of owned themes; tapping applies it via PUT /profile/theme.
class ThemeSelectorScreen extends StatefulWidget {
  const ThemeSelectorScreen({super.key});

  @override
  State<ThemeSelectorScreen> createState() => _ThemeSelectorScreenState();
}

class _ThemeSelectorScreenState extends State<ThemeSelectorScreen> {
  List<dynamic> _owned = [];
  String? _currentThemeId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
        _owned = all.where((i) => i['shop_items']?['category'] == 'theme').toList();
        _currentThemeId = results[1].data['data']?['equipped_theme_id'];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _apply(Map<String, dynamic> inv) async {
    try {
      await ApiService.put('/profile/theme', data: {'item_id': inv['item_id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${inv['shop_items']?['name']} applied')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: EdgeInsets.all(16.w),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12.w, mainAxisSpacing: 12.h,
                childAspectRatio: 1.2,
              ),
              itemCount: _owned.length,
              itemBuilder: (context, index) {
                final item = (_owned[index]['shop_items'] as Map<String, dynamic>?) ?? {};
                final selected = _owned[index]['item_id'] == _currentThemeId;
                return Card(
                  color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                  child: InkWell(
                    onTap: () => _apply(_owned[index] as Map<String, dynamic>),
                    borderRadius: BorderRadius.circular(10.r),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.palette),
                      SizedBox(height: 8.h),
                      Text(item['name'] ?? '', style: TextStyle(fontSize: 13.sp)),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
