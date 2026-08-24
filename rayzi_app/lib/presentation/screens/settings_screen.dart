import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/theme.dart';
import '../blocs/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ---- Appearance: Day / Night / System -------------------------
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 4.h),
            child: Text('Appearance',
                style:
                    TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.mode,
            builder: (context, current, _) => Column(
              children: [
                _modeTile(context, ThemeMode.light, Icons.light_mode_outlined,
                    'Light', current),
                _modeTile(context, ThemeMode.dark, Icons.dark_mode_outlined,
                    'Dark', current),
                _modeTile(
                    context,
                    ThemeMode.system,
                    Icons.brightness_auto_outlined,
                    'System Default',
                    current),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            trailing: Text(_version),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About PHM Live'),
            subtitle: const Text('Connect. Stream. Earn.'),
            onTap: () => Navigator.pushNamed(context, '/about'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              context.read<AuthBloc>().add(AuthLogoutRequested());
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _modeTile(BuildContext context, ThemeMode value, IconData icon,
      String label, ThemeMode current) {
    return RadioListTile<ThemeMode>(
      value: value,
      groupValue: current,
      onChanged: (next) {
        if (next != null) AppThemeController.setMode(next);
      },
      secondary: Icon(icon),
      title: Text(label, style: TextStyle(fontSize: 15.sp)),
      activeColor: Theme.of(context).colorScheme.primary,
    );
  }
}
