import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/routes.dart';
import '../../services/api_service.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_button.dart';
import '../../features/shared/decorated_widgets.dart';
import '../../features/profile/history_screen.dart';
import '../../features/profile/block_list_screen.dart';
import 'leaderboard_screen.dart' show showLeaderboardSheet;

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final response = await ApiService.get('/profile/summary');
      if (!mounted) return;
      setState(() => _summary = response.data['data']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile summary: $e')));
    }
  }

  String get _userId => _summary?['id'] as String? ?? '';

  void _shareApp() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final playStoreUrl = 'https://play.google.com/store/apps/details?id=${info.packageName}';
      await Share.share(
        'Check out ${info.appName}!\n$playStoreUrl',
        subject: '${info.appName} - Live Streaming',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ],
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state is AuthAuthenticated) {
            final metadata = state.user.userMetadata ?? {};
            final frameTier = (_summary?['equipped_frame'] as Map<String, dynamic>?)?['tier'] as String?;
            return SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  DecoratedAvatar(avatarUrl: metadata['avatar_url'] as String? ?? '', radius: 44, frameGradient: ProfileCosmetics.frameFor(frameTier)),
                  SizedBox(height: 12.h),
                  DecoratedUsername(
                    profile: {
                      'display_name': metadata['display_name'] ?? _summary?['display_name'] ?? 'User',
                      'username': metadata['username'] ?? '',
                      'is_verified': _summary?['is_verified'] ?? false,
                      'name_effect': _summary?['name_effect'],
                    },
                    baseStyle: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
                  ),
                  // ID row with copy button.
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _userId));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ID copied')));
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('ID: ${_userId.isEmpty ? '…' : _userId.substring(0, _userId.length.clamp(0, 8))}',
                            style: TextStyle(fontSize: 12.sp, color: Colors.grey)),
                        SizedBox(width: 4.w),
                        Icon(Icons.copy, size: 13.r, color: Colors.grey),
                      ]),
                    ),
                  ),
                  // Diamonds / level / experience pills.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill('💎 ${_summary?['diamonds'] ?? 0}'),
                      SizedBox(width: 8.w),
                      _pill('⭐ Level ${_summary?['level'] ?? 1}'),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat('${_summary?['friends_count'] ?? 0}', 'Friends'),
                      _buildStat('${_summary?['follower_count'] ?? 0}', 'Followers'),
                      _buildStat('${_summary?['following_count'] ?? 0}', 'Following'),
                    ],
                  ),
                  SizedBox(height: 24.h),
                  // ---- Section: Earnings & Finance ----
                  _sectionHeader('Earnings & Finance'),
                  _menu(Icons.account_balance_wallet, 'Wallet', AppRoutes.wallet),
                  _menu(Icons.shopping_bag_outlined, 'Buy Coins', '/buy-coins'),
                  _menu(Icons.payments_outlined, 'Withdraw', '/withdraw'),
                  _menu(Icons.fact_check_outlined, 'Wallet Ledger', '/wallet-ledger'),
                  _menu(Icons.history, 'Transaction History', null,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()))),
                  SizedBox(height: 8.h),
                  // ---- Section: Shop & Items ----
                  _sectionHeader('Shop & Items'),
                  _menu(Icons.emoji_events, 'Leaderboard', null,
                      onTap: () => showLeaderboardSheet(context)),
                  _menu(Icons.workspace_premium, 'Shop (KING / CROWN)', '/shop'),
                  _menu(Icons.diamond, 'VVIP / VIP', '/shop', onTap: () => Navigator.pushNamed(context, '/shop')),
                  _menu(Icons.card_giftcard, 'My Items', '/inventory'),
                  SizedBox(height: 8.h),
                  // ---- Section: Social ----
                  _sectionHeader('Social'),
                  _menu(Icons.block, 'Block List', null,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockListScreen()))),
                  _menu(Icons.receipt_long, 'Recharge from Reseller', '/reseller-recharge'),
                  if (_summary?['is_reseller'] == true)
                    _menu(Icons.storefront, 'Reseller Dashboard', '/reseller-dashboard'),
                  _menu(Icons.videogame_asset, 'Mini-Games', '/games'),
                  _menu(Icons.live_tv, 'Host Request', '/host-request'),
                  SizedBox(height: 8.h),
                  // ---- Section: Settings ----
                  _sectionHeader('Settings & Support'),
                  _menu(Icons.palette, 'Theme', '/themes'),
                  _menu(Icons.auto_awesome, 'Entry Animation', '/entry-animations'),
                  _menu(Icons.edit, 'Edit Profile', AppRoutes.editProfile),
                  _menu(Icons.share, 'Share App', null, onTap: _shareApp),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Logout', style: TextStyle(color: Colors.red)),
                    onTap: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
                  ),
                ],
              ),
            );
          }
          if (state is AuthGuest) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_circle_outlined, size: 80.r, color: Colors.grey),
                  SizedBox(height: 16.h),
                  Text(
                    'You are browsing as a guest',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Sign in to unlock your profile, wallet and gifts',
                    style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48.w),
                    child: CustomButton(
                      text: 'Sign In / Sign Up',
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context, AppRoutes.login, (route) => false,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(text, style: TextStyle(fontSize: 12.sp)),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 4.h),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.grey[500])),
      ),
    );
  }

  Widget _menu(IconData icon, String label, String? routeName, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label, style: TextStyle(fontSize: 14.sp)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap ?? () => Navigator.pushNamed(context, routeName!).then((_) => _loadSummary()),
    );
  }

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
      ],
    );
  }
}
