import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'services/admin_api.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/users_screen.dart';
import 'presentation/screens/streams_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/screens/gifts_screen.dart';
import 'presentation/screens/withdrawals_screen.dart';
import 'presentation/screens/expansion_screen.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rayzi Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AdminLoginScreen(),
        '/dashboard': (context) => _guarded(const DashboardScreen()),
        '/users': (context) => _guarded(const UsersScreen()),
        '/streams': (context) => _guarded(const StreamsScreen()),
        '/reports': (context) => _guarded(const ReportsScreen()),
        '/gifts': (context) => _guarded(const GiftsScreen()),
        '/withdrawals': (context) => _guarded(const WithdrawalsScreen()),
        '/expansion': (context) => _guarded(const ExpansionScreen()),
      },
    );
  }

  /// Route guard — every protected screen verifies the session belongs to an
  /// admin before rendering; otherwise the user lands back on login.
  Widget _guarded(Widget screen) {
    return FutureBuilder<bool>(
      future: AdminApi.restoreSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data != true) {
          if (kDebugMode) debugPrint('Admin route blocked: no admin session');
          return const AdminLoginScreen();
        }
        return screen;
      },
    );
  }
}
