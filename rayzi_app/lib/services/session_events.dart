import 'dart:async';

/// Global session-lifecycle signals emitted by the Dio 401 interceptor.
///
/// Only fired when a token was actually present and got invalidated — the
/// legitimate guest flow never triggers it (guests send no token).
class SessionEvents {
  static final _controller = StreamController<String>.broadcast();

  /// Emits `'expired'` when an authenticated session dies server-side.
  static Stream<String> get stream => _controller.stream;

  static void emitSessionExpired() {
    if (!_controller.isClosed) _controller.add('expired');
  }

  static void dispose() => _controller.close();
}
