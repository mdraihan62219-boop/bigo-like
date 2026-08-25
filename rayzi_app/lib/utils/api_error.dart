import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

String friendlyError(Object e) {
  if (e is DioException) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Connection timed out. Please try again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection.';
    }
    final statusCode = e.response?.statusCode;
    if (statusCode != null) {
      if (statusCode == 401) return 'Invalid credentials.';
      if (statusCode == 400) return 'Bad request.';
      if (statusCode == 404) return 'Not found.';
      if (statusCode == 500) return 'Server error.';
    }
    final body = e.response?.data;
    if (body is Map) {
      final error = body['error'] ?? body['message'];
      if (error is String && error.isNotEmpty) return error;
    }
    if (e.message != null) return e.message!;
  }
  final msg = e.toString();
  if (msg.startsWith('Exception: ')) {
    return msg.substring('Exception: '.length);
  }
  return msg;
}

void showApiError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(friendlyError(e))),
  );
}
