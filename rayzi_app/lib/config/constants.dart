class AppConstants {
  static const String appName = 'Rayzi';

  /// Override at build time for real devices:
  ///   flutter build apk --dart-define=API_BASE_URL=http://<your-lan-ip>:3000/api/v1 \
  ///                    --dart-define=SOCKET_URL=http://<your-lan-ip>:3000
  /// Default 10.0.2.2 = Android emulator loopback to the host machine.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String supabaseUrl = 'https://yuokeoduqtxgfdlwuaaw.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1b2tlb2R1cXR4Z2ZkbHd1YWF3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MDQyODIsImV4cCI6MjEwMjk4MDI4Mn0.h2nJuTSy_a0vAoweM0OIIYjA4ytM9qMdsd_sgJ5e0nc';
  static const String agoraAppId = 'your-agora-app-id';

  static const int paginationLimit = 20;
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration socketTimeout = Duration(seconds: 10);
}
