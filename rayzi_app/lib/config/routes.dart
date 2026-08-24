import 'package:flutter/material.dart';
import '../presentation/screens/screens.dart';
import '../features/shop/shop_screens.dart';
import '../features/shop/inventory_screen.dart';
import '../features/feed/feed_screens.dart';
import '../features/host/host_screens.dart';
import '../features/pk/pk_screens.dart';
import '../features/profile/theme_selector_screen.dart';
import '../features/profile/entry_animation_selector_screen.dart';
import '../features/inbox/inbox_screens.dart';
import '../features/wallet/wallet_v2_screens.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String editProfile = '/edit-profile';
  static const String stream = '/stream';
  static const String createStream = '/create-stream';
  static const String postDetail = '/post-detail';
  static const String createPost = '/create-post';
  static const String reels = '/reels';
  static const String room = '/room';
  static const String createRoom = '/create-room';
  static const String wallet = '/wallet';
  static const String giftStore = '/gift-store';
  static const String leaderboard = '/leaderboard';
  static const String search = '/search';
  static const String notifications = '/notifications';
  static const String settings = '/settings';
  static const String about = '/about';
  static const String chat = '/chat';
  static const String userProfile = '/user-profile';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    login: (context) => const LoginScreen(),
    register: (context) => const RegisterScreen(),
    home: (context) => const HomeScreen(),
    profile: (context) => const ProfileScreen(),
    editProfile: (context) => const EditProfileScreen(),
    stream: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      return StreamScreen(
        stream: args is Map<String, dynamic> ? args : <String, dynamic>{},
      );
    },
    createStream: (context) => const CreateStreamScreen(),
    postDetail: (context) => const ComingSoonScreen(title: 'Post details'),
    createPost: (context) => const CreatePostScreen(),
    reels: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final map = args is Map ? args : const {};
      return ReelsScreen(
        posts: map['posts'] as List<dynamic>?,
        initialIndex: (map['initialIndex'] as int?) ?? 0,
      );
    },
    room: (context) => const ComingSoonScreen(title: 'Audio room'),
    createRoom: (context) => const ComingSoonScreen(title: 'Create audio room'),
    giftStore: (context) => const ComingSoonScreen(title: 'Gift store'),
    chat: (context) => const ComingSoonScreen(title: 'Chat'),
    userProfile: (context) => const ComingSoonScreen(title: 'User profile'),
    wallet: (context) => const WalletScreen(),
    leaderboard: (context) => const LeaderboardScreen(),
    search: (context) => const SearchScreen(),
    notifications: (context) => const NotificationsScreen(),
    settings: (context) => const SettingsScreen(),
    // ---- v2 expansion routes ----
    '/shop': (context) => const ShopHomeScreen(),
    '/shop-tier': (context) {
      final tier = ModalRoute.of(context)?.settings.arguments;
      return ShopTierScreen(tier: tier is String ? tier : 'vip');
    },
    '/inventory': (context) => const InventoryScreen(),
    '/create-story': (context) => const CreateStoryScreen(),
    '/story-viewer': (context) => const StoryViewerScreen(),
    '/newsfeed': (context) => const NewsfeedScreen(),
    '/reseller-recharge': (context) => const RechargeFromResellerScreen(),
    '/my-recharge-requests': (context) => const MyRechargeRequestsScreen(),
    '/host-request': (context) => const HostRequestScreen(),
    '/themes': (context) => const ThemeSelectorScreen(),
    '/entry-animations': (context) => const EntryAnimationSelectorScreen(),
    '/inbox': (context) => const InboxListScreen(),
    '/conversation': (context) => const ConversationScreen(),
    // ---- wallet economy v2 ----
    '/buy-coins': (context) => const BuyCoinsScreen(),
    '/withdraw': (context) => const WithdrawScreen(),
    '/wallet-ledger': (context) => const WalletLedgerScreen(),
    '/pk-battle': (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final id = args is Map ? args['id'] as String? : null;
      return PkBattleView(battleId: id ?? '');
    },
  };
}
