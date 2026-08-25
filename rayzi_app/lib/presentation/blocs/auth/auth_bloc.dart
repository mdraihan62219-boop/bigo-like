import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/api_service.dart';
import '../../../services/google_auth_service.dart';
import '../../../services/token_store.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthGuestRequested>(_onGuestRequested);
    on<AuthGoogleRequested>(_onGoogleRequested);
  }

  /// Extract a clean, user-facing error message from a caught exception.
  static String _friendlyError(Object e) {
    if (e is DioException) {
      // Backend returns { success: false, error: "..." } for 4xx responses.
      final body = e.response?.data;
      if (body is Map && body['error'] is String) return body['error'] as String;
      if (body is Map && body['message'] is String) return body['message'] as String;
      if (e.response?.statusCode == 401) return 'Invalid credentials';
      if (e.response?.statusCode == 400) return 'Bad request — please check your input';
      if (e.type == DioExceptionType.connectionTimeout) return 'Connection timed out';
      if (e.type == DioExceptionType.connectionError) return 'No internet connection';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _onAuthCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session?.user != null) {
      emit(AuthAuthenticated(session!.user));
      return;
    }

    // Restore from a previously issued backend JWT.
    final storedToken = await TokenStore.read();
    if (storedToken == null || storedToken.isEmpty) {
      emit(AuthUnauthenticated());
      return;
    }

    try {
      final me = await ApiService.get('/auth/me');
      final rawUser = me.data['data']?['user'] ?? me.data['data'];
      final user = rawUser == null ? null : User.fromJson(Map<String, dynamic>.from(rawUser as Map));
      if (user == null) throw Exception('Invalid user payload');
      emit(AuthAuthenticated(user));
    } catch (_) {
      await TokenStore.clear();
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(AuthLoginRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await ApiService.post('/auth/login', data: {
        'email': event.email, 'password': event.password,
      });
      emit(AuthAuthenticated(await _persistSession(response.data['data'])));
    } catch (e) {
      emit(AuthError(_friendlyError(e)));
    }
  }

  Future<void> _onRegisterRequested(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final response = await ApiService.post('/auth/register', data: {
        'email': event.email, 'password': event.password,
        'username': event.username, 'display_name': event.displayName,
      });
      emit(AuthAuthenticated(await _persistSession(response.data['data'])));
    } catch (e) {
      emit(AuthError(_friendlyError(e)));
    }
  }

  /// Persists the backend JWT for ApiService/SocketService and returns the
  /// parsed Supabase [User]. The backend issues its own JWT — we deliberately
  /// do NOT feed it into Supabase client auth (`setSession` expects a genuine
  /// Supabase session).
  Future<User> _persistSession(dynamic payload) async {
    final data = Map<String, dynamic>.from(payload as Map);
    final token = data['token'] as String?;
    final rawUser = data['user'];

    if (token == null || token.isEmpty || rawUser == null) {
      throw Exception('Invalid auth response');
    }

    final user = User.fromJson(Map<String, dynamic>.from(rawUser as Map));
    if (user == null) throw Exception('Invalid user payload');

    await TokenStore.save(token);
    return user;
  }

  Future<void> _onGoogleRequested(AuthGoogleRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final idToken = await GoogleAuthService.getIdToken();
      if (idToken == null) {
        // User closed the picker — back to the form, no error.
        emit(AuthUnauthenticated());
        return;
      }
      final response = await ApiService.post('/auth/social', data: {
        'provider': 'google', 'token': idToken,
      });
      emit(AuthAuthenticated(await _persistSession(response.data['data'])));
    } on GoogleAuthConfigurationException catch (e) {
      emit(AuthError(_friendlyError(e)));
    } catch (e) {
      emit(AuthError(_friendlyError(e)));
    }
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await Supabase.instance.client.auth.signOut();
    try {
      await GoogleAuthService.signOut();
    } catch (_) {
      // Google sign-in may be unconfigured — nothing to reset.
    }
    await TokenStore.clear();
    emit(AuthUnauthenticated());
  }

  Future<void> _onGuestRequested(AuthGuestRequested event, Emitter<AuthState> emit) async {
    await Supabase.instance.client.auth.signOut();
    await TokenStore.clear();
    emit(AuthGuest());
  }
}
