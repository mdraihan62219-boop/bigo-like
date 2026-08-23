part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String email, password;
  AuthLoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}

class AuthRegisterRequested extends AuthEvent {
  final String email, password, username, displayName;
  AuthRegisterRequested(this.email, this.password, this.username, this.displayName);
  @override
  List<Object?> get props => [email, password, username, displayName];
}

class AuthLogoutRequested extends AuthEvent {}

class AuthGuestRequested extends AuthEvent {}

class AuthGoogleRequested extends AuthEvent {}
