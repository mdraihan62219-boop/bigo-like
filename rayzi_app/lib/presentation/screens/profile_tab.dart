import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/routes.dart';
import '../blocs/auth/auth_bloc.dart';
import '../widgets/custom_button.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

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
            final metadata = state.user.userMetadata ?? {};            return SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50.r,
                    backgroundImage: CachedNetworkImageProvider(
                      metadata['avatar_url'] as String? ?? 'https://via.placeholder.com/150',
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    metadata['display_name'] as String? ?? 'User',
                    style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '@${metadata['username'] as String? ?? 'user'}',
                    style: TextStyle(fontSize: 16.sp, color: Colors.grey),
                  ),
                  SizedBox(height: 24.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat('0', 'Posts'),
                      _buildStat('0', 'Followers'),
                      _buildStat('0', 'Following'),
                    ],
                  ),
                  SizedBox(height: 24.h),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet),
                    title: const Text('Wallet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.wallet),
                  ),
                  ListTile(
                    leading: const Icon(Icons.emoji_events),
                    title: const Text('Leaderboard'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.leaderboard),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit Profile'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, AppRoutes.editProfile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Logout', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      context.read<AuthBloc>().add(AuthLogoutRequested());
                    },
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

  Widget _buildStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.grey)),
      ],
    );
  }
}
