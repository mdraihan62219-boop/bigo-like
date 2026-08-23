import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/constants.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'services/api_service.dart';
import 'services/session_events.dart';
import 'presentation/blocs/auth/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Records the top-most route name so the session-expiry listener can tell
/// whether we're already on the login screen.
class CurrentRouteObserver extends NavigatorObserver {
  static String? currentName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentName = route.settings.name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentName = previousRoute?.settings.name;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentName = newRoute?.settings.name;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentName = previousRoute?.settings.name;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  ApiService.init();

  runApp(const RayziApp());
}

class RayziApp extends StatefulWidget {
  const RayziApp({super.key});

  @override
  State<RayziApp> createState() => _RayziAppState();
}

class _RayziAppState extends State<RayziApp> {
  StreamSubscription<String>? _sessionSub;
  final _routeObserver = CurrentRouteObserver();

  @override
  void initState() {
    super.initState();
    // A 401 on any authenticated call bounces the user to login globally —
    // no more stranded screens with raw DioException snackbars.
    _sessionSub = SessionEvents.stream.listen((_) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      if (CurrentRouteObserver.currentName == AppRoutes.login) return;
      if (!mounted) return;
      nav.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
        const SnackBar(content: Text('Session expired — please sign in again')),
      );
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (context, child) {
        return BlocProvider(
          create: (context) => AuthBloc(),
          child: MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            initialRoute: AppRoutes.splash,
            routes: AppRoutes.routes,
            navigatorKey: navigatorKey,
            navigatorObservers: [_routeObserver],
          ),
        );
      },
    );
  }
}
