/// Formats large numbers for compact display: 1.2K, 3.4M, 1.0B.
String formatNumber(num n) {
  if (n >= 1000000000) {
    final v = n / 1000000000;
    return '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}B';
  }
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)}K';
  }
  return '$n';
}

/// Basic email sanity check used before hitting the API.
bool validateEmail(String email) {
  final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  return re.hasMatch(email.trim());
}
