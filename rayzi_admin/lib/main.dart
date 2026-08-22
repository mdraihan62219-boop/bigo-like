import 'package:flutter/material.dart';
import 'package:url_strategy/url_strategy.dart';
import 'services/admin_api.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();

  AdminApi.init();

  runApp(const AdminApp());
}
