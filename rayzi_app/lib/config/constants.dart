class AppConstants {
  static const String appName = 'PHM Live';

  /// Override at build time for local development:
  ///   flutter build apk --dart-define=API_BASE_URL=http://<your-lan-ip>:3000/api/v1 \
  ///                    --dart-define=SOCKET_URL=http://<your-lan-ip>:3000
  /// Production default: Render deployment.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://bigo-like-1.onrender.com/api/v1',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'https://bigo-like-1.onrender.com',
  );

  static const String supabaseUrl = 'https://yuokeoduqtxgfdlwuaaw.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl1b2tlb2R1cXR4Z2ZkbHd1YWF3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc0MDQyODIsImV4cCI6MjEwMjk4MDI4Mn0.h2nJuTSy_a0vAoweM0OIIYjA4ytM9qMdsd_sgJ5e0nc';
  static const String agoraAppId = 'your-agora-app-id';

  /// Google Cloud "Web application" OAuth client ID (NOT the Android one).
  /// Required for Continue-with-Google ID tokens. Override at build time:
  ///   flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID=<id>.apps.googleusercontent.com
  /// One-time setup: create the Web + Android OAuth clients in Google Cloud
  /// Console, register this app's SHA-1 with the Android client.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static const int paginationLimit = 20;
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration socketTimeout = Duration(seconds: 10);
}
