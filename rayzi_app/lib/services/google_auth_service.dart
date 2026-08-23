import 'package:google_sign_in/google_sign_in.dart';
import '../config/constants.dart';

class GoogleAuthService {
  static GoogleSignIn? _instance;

  static GoogleSignIn get _googleSignIn {
    _instance ??= GoogleSignIn(serverClientId: AppConstants.googleWebClientId);
    return _instance!;
  }

  /// Runs the native Google sign-in flow and returns the ID token,
  /// or null when the user closes the account picker.
  static Future<String?> getIdToken() async {
    if (AppConstants.googleWebClientId.isEmpty) {
      throw GoogleAuthConfigurationException();
    }
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Google sign-in returned no ID token');
    }
    return idToken;
  }

  static Future<void> signOut() => _googleSignIn.signOut();
}

class GoogleAuthConfigurationException implements Exception {
  @override
  String toString() =>
      'Google sign-in is not configured. Build with '
      '--dart-define=GOOGLE_WEB_CLIENT_ID=<your-web-client-id>';
}
