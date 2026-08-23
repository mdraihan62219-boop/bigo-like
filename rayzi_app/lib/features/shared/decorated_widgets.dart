import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Avatar with optional equipped frame overlay ring.
class DecoratedAvatar extends StatelessWidget {
  const DecoratedAvatar({
    super.key,
    required this.avatarUrl,
    this.radius = 18,
    this.frameColor,
    this.frameGradient,
  });

  final String? avatarUrl;
  final double radius;
  final Color? frameColor;
  final List<Color>? frameGradient;

  @override
  Widget build(BuildContext context) {
    final hasFrame = frameColor != null || (frameGradient != null && frameGradient!.isNotEmpty);
    final avatar = CircleAvatar(
      radius: radius.r,
      backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
          ? CachedNetworkImageProvider(avatarUrl!)
          : null,
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? Icon(Icons.person, size: radius.r)
          : null,
    );
    if (!hasFrame) return avatar;

    // Frame drawn as a 2.5px gradient ring around the avatar.
    final ringWidth = (radius * 0.16).r;
    return Container(
      width: (radius * 2 + ringWidth * 2.6).r,
      height: (radius * 2 + ringWidth * 2.6).r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: frameGradient != null && frameGradient!.isNotEmpty
            ? LinearGradient(colors: frameGradient!)
            : null,
        color: frameGradient == null ? frameColor : null,
      ),
      padding: EdgeInsets.all(ringWidth),
      child: CircleAvatar(
        radius: radius.r,
        backgroundColor: Colors.black87,
        backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
            ? CachedNetworkImageProvider(avatarUrl!)
            : null,
        child: (avatarUrl == null || avatarUrl!.isEmpty)
            ? Icon(Icons.person, size: radius.r)
            : null,
      ),
    );
  }
}

/// Rich-text username rendering `name_effect` JSONB from profiles:
/// prefix emojis + gradient display name + suffix emojis.
/// Never renders "Admin"/"Official" text unless the user is verified/admin.
class DecoratedUsername extends StatelessWidget {
  const DecoratedUsername({
    super.key,
    required this.profile,
    this.baseStyle,
    this.showVerifiedBadge = true,
  });

  final Map<String, dynamic> profile;
  final TextStyle? baseStyle;
  final bool showVerifiedBadge;

  @override
  Widget build(BuildContext context) {
    final effect = profile['name_effect'];
    final displayName = (profile['display_name'] as String?) ??
        (profile['username'] as String?) ?? 'user';
    final style = baseStyle ?? TextStyle(fontSize: 13.sp);

    // Trust signals only from real roles — never from user input.
    final isStaff = profile['is_verified'] == true ||
        profile['role'] == 'admin' || profile['role'] == 'host';

    Map<String, dynamic>? cfg;
    if (effect is Map<String, dynamic>) {
      cfg = effect;
    } else if (effect is Map) {
      cfg = Map<String, dynamic>.from(effect);
    }

    final prefix = _emojis(cfg?['prefix_emojis']);
    final suffix = _emojis(cfg?['suffix_emojis']);
    final colors = <String>[];
    if (cfg?['gradient_colors'] is List) {
      for (final c in (cfg!['gradient_colors'] as List)) {
        if (c is String) colors.add(c);
      }
    }

    InlineSpan nameSpan;
    if (colors.length >= 2) {
      // ShaderMask approximates a text gradient.
      nameSpan = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: colors.map(_parseColor).toList(),
          ).createShader(bounds),
          child: Text(displayName,
              style: style.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      );
    } else {
      nameSpan = TextSpan(text: displayName, style: style);
    }

    return Text.rich(
      TextSpan(children: [
        if (prefix.isNotEmpty) TextSpan(text: '$prefix ', style: style),
        nameSpan,
        if (suffix.isNotEmpty) TextSpan(text: ' $suffix', style: style),
        if (showVerifiedBadge && isStaff) ...[
          const WidgetSpan(child: SizedBox(width: 4)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(profile['role'] == 'admin'
                ? Icons.verified_user
                : Icons.verified, color: Colors.lightBlueAccent, size: style.fontSize ?? 14.sp),
          ),
        ],
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _emojis(dynamic list) {
    if (list is List && list.isNotEmpty) {
      return list.whereType<String>().join();
    }
    return '';
  }

  static Color _parseColor(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFFFFF);
  }
}

/// Maps a profile row onto DecoratedAvatar props via equipped_frame_id lookups.
class ProfileCosmetics {
  static const frameColors = {
    'king': [Color(0xFFF5C518), Color(0xFFB8860B)],
    'crown': [Color(0xFFC0C0C0), Color(0xFF808080)],
    'vvip': [Color(0xFFFF6B9D), Color(0xFF7B2FBE)],
    'vip': [Color(0xFF00D4FF), Color(0xFF0066FF)],
  };

  /// Returns a gradient for a known tier or a default gold for unknown ids.
  static List<Color>? frameFor(String? equippedFrameId) {
    if (equippedFrameId == null || equippedFrameId.isEmpty) return null;
    return frameColors[equippedFrameId] ?? const [Color(0xFFF5C518), Color(0xFFFFF3B0)];
  }
}
