import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../config/constants.dart';
import 'token_store.dart';

class SocketService {
  static socket_io.Socket? _socket;

  static Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;

    final token = await TokenStore.read();

    _socket = socket_io.io(AppConstants.socketUrl, socket_io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .enableAutoConnect()
      .build());

    _socket!.onConnect((_) => debugPrint('Socket connected'));
    _socket!.onDisconnect((_) => debugPrint('Socket disconnected'));
    _socket!.onError((err) => debugPrint('Socket error: $err'));
  }

  static void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  static void joinStream(String streamId) {
    _socket?.emit('join-stream', streamId);
  }

  static void leaveStream(String streamId) {
    _socket?.emit('leave-stream', streamId);
  }

  static void sendChatMessage(String streamId, String message) {
    _socket?.emit('chat-message', {'streamId': streamId, 'message': message});
  }

  static void sendGift(String streamId, String giftId, String receiverId) {
    _socket?.emit('send-gift', {'streamId': streamId, 'giftId': giftId, 'receiverId': receiverId});
  }

  static void onChatMessage(Function(dynamic) callback) {
    _socket?.on('chat-message', (data) => callback(data));
  }

  static void offChatMessage() {
    _socket?.off('chat-message');
  }

  static void onGiftReceived(Function(dynamic) callback) {
    _socket?.on('gift-received', (data) => callback(data));
  }

  static void onUserJoined(Function(dynamic) callback) {
    _socket?.on('user-joined', (data) => callback(data));
  }

  static void onUserLeft(Function(dynamic) callback) {
    _socket?.on('user-left', (data) => callback(data));
  }

  static void offUserJoined() {
    _socket?.off('user-joined');
  }

  static void offUserLeft() {
    _socket?.off('user-left');
  }

  static void offGiftReceived() {
    _socket?.off('gift-received');
  }

  static void onPkMatched(Function(dynamic) callback) {
    _socket?.on('pk-matched', (data) => callback(data));
  }

  static void offPkMatched() {
    _socket?.off('pk-matched');
  }

  /// Joins the pseudo-room used for PK battle score pushes
  /// (backend emits pk-score-update to stream_<battleId>).
  static void joinBattle(String battleId) {
    _socket?.emit('join-stream', battleId);
  }

  static void leaveBattle(String battleId) {
    _socket?.emit('leave-stream', battleId);
  }

  static void onPkScoreUpdate(Function(dynamic) callback) {
    _socket?.on('pk-score-update', (data) => callback(data));
  }

  static void offPkScoreUpdate() {
    _socket?.off('pk-score-update');
  }
}
