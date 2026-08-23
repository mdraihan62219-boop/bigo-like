import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          SizedBox(height: 8.h),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24.r),
              child: Image.asset(
                'assets/images/logo.jpeg',
                width: 96.w,
                height: 96.w,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Center(
            child: Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Center(
            child: Text(
              '"Your Stage, Your Stream, Your Earning"',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(height: 16.h),
          const _Section(
            title: 'About PHM Live',
            body:
                'PHM Live is a next-generation live streaming and social platform '
                'where creative individuals can showcase their talent, connect '
                'with audiences, and earn money at the same time. Combining live '
                'streaming, short videos, video calls, and gaming, PHM Live '
                'delivers a complete entertainment experience in one app.\n\n'
                'PHM Live - Connect. Stream. Earn.',
          ),
          const _FeatureGroup(
            title: 'Live Streaming',
            items: [
              'Single live streaming - start your own solo broadcast',
              'Multi live (group live) - stream together in one session',
              'PK battles - real-time streamer competitions by gift points',
              'Live chat & comments during sessions',
              'Follow system with go-live notifications',
            ],
          ),
          const _FeatureGroup(
            title: 'Video Calling',
            items: [
              'Random video calls with stranger matching',
              '1-to-1 private video calls',
              'Gender/interest-based matching filters',
              'Coin charging per minute or per call',
            ],
          ),
          const _FeatureGroup(
            title: 'Voice Chat Rooms & Short Videos',
            items: [
              'Multi-user voice rooms with host/co-host controls',
              'Virtual gifts inside voice rooms',
              'TikTok-style vertical short video feed',
              'Like, comment, share and follow creators',
              'Trending and personalized feeds',
            ],
          ),
          const _FeatureGroup(
            title: 'Economy & Rewards',
            items: [
              'Diamond & coin wallet for gifts',
              'Gift store with themed animated gifts',
              'Withdraw system - convert diamonds to real money',
              'Recharge via payment gateways',
              'In-app gaming zone with points and leaderboards',
              'VIP badges, frames and premium perks',
              'Referral bonuses and agency/host commissions',
            ],
          ),
          SizedBox(height: 16.h),
          const Divider(),
          const ListTile(
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),
          const ListTile(
            title: Text('Developed by'),
            subtitle: Text('PHM Live Team'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 6.h),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        SizedBox(height: 12.h),
      ],
    );
  }
}

class _FeatureGroup extends StatelessWidget {
  final String title;
  final List<String> items;

  const _FeatureGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 6.h),
            ...items.map(
              (item) => Padding(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16.sp,
                        color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(item,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
