import 'package:flutter/material.dart';
import '../../config/routes.dart';
import 'live_tab.dart';
import 'profile_tab.dart';
import '../../features/feed/feed_screens.dart';
import 'reels_screen.dart';
import 'rooms_tab.dart';
import '../../features/inbox/inbox_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = const [
    LiveTab(),
    NewsfeedScreen(),
    ReelsTab(),
    RoomsTab(),
    InboxListScreen(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.live_tv), label: 'Live'),
          BottomNavigationBarItem(icon: Icon(Icons.article), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: 'Reels'),
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room), label: 'Rooms'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
        ? FloatingActionButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.createStream),
            child: const Icon(Icons.videocam),
          )
        : null,
    );
  }
}
