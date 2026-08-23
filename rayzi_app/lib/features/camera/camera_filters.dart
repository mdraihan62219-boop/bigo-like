import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/api_service.dart';

/// One of 10 real-time filter presets, implemented as a ColorFilter matrix
/// so it renders identically on camera previews and captured media.
class CameraFilter {
  const CameraFilter(this.id, this.label, this.matrix);
  final String id;
  final String label;
  final List<double> matrix; // 4x5 color matrix

  ColorFiltered apply(Widget child) => ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: child,
      );
}

class CameraFilters {
  static const natural = CameraFilter('natural', 'Natural', [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  /// Beauty Smooth: soft desaturation + slight brightness.
  static final beautySmooth = _brightness(0.06, saturation: 0.92);

  static const warm = CameraFilter('warm', 'Warm', [
    1.08, 0.02, 0, 0, 8, //
    0.02, 1.0, 0, 0, 2, //
    0, 0, 0.94, 0, -4, //
    0, 0, 0, 1, 0,
  ]);

  static const cool = CameraFilter('cool', 'Cool', [
    0.94, 0, 0.03, 0, -3, //
    0, 0.99, 0.01, 0, 0, //
    0.02, 0.02, 1.08, 0, 10, //
    0, 0, 0, 1, 0,
  ]);

  static const vintage = CameraFilter('vintage', 'Vintage', [
    0.9, 0.05, 0.05, 0, 12, //
    0.05, 0.85, 0.08, 0, 6, //
    0.05, 0.1, 0.75, 0, -6, //
    0, 0, 0, 1, 0,
  ]);

  static const blackWhite = CameraFilter('bw', 'B&W', [
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0.33, 0.59, 0.11, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  static const vivid = CameraFilter('vivid', 'Vivid', [
    1.25, -0.12, -0.12, 0, 0, //
    -0.12, 1.25, -0.12, 0, 0, //
    -0.12, -0.12, 1.25, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  static final softGlow = _brightness(0.10, saturation: 1.04, contrast: 0.95);

  static const cinematic = CameraFilter('cinematic', 'Cinematic', [
    1.06, 0, -0.06, 0, -6, //
    0, 1.0, -0.02, 0, -2, //
    0.02, 0.04, 1.02, 0, 6, //
    0, 0, 0, 1, 0,
  ]);

  static final nightBright = _brightness(0.16, saturation: 1.02);

  static List<CameraFilter> all = [
    natural, beautySmooth, warm, cool, vintage,
    blackWhite, vivid, softGlow, cinematic, nightBright,
  ];

  static CameraFilter byId(String id) =>
      all.firstWhere((f) => f.id == id, orElse: () => natural);

  static CameraFilter _brightness(double amount, {double saturation = 1.0, double contrast = 1.0}) {
    final s = saturation;
    final c = contrast;
    // Saturate then contrast then offset — composed into one matrix.
    final sat = <double>[
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    final off = (255 * amount).roundToDouble();
    final bright = <double>[
      c, 0, 0, 0, off / 2, //
      0, c, 0, 0, off / 2, //
      0, 0, c, 0, off / 2, //
      0, 0, 0, 1, 0,
    ];
    return CameraFilter('b${amount.toStringAsFixed(2)}s$s', '', _mul(sat, bright));
  }

  static List<double> _mul(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (int r = 0; r < 4; r++) {
      for (int c = 0; c < 5; c++) {
        var v = 0.0;
        for (int k = 0; k < 5; k++) {
          v += a[r * 5 + k] * b[k * 5 + c];
        }
        out[r * 5 + c] = v;
      }
    }
    return out;
  }
}

/// Horizontal carousel of 10 live filters + beauty sliders.
class CameraFilterCarousel extends StatefulWidget {
  const CameraFilterCarousel({
    super.key,
    required this.selectedId,
    required this.onFilterChanged,
    required this.beautyLevel,
    required this.brightness,
    required this.onBeautyChanged,
    required this.onBrightnessChanged,
  });

  final String selectedId;
  final ValueChanged<String> onFilterChanged;
  final double beautyLevel;
  final double brightness;
  final ValueChanged<double> onBeautyChanged;
  final ValueChanged<double> onBrightnessChanged;

  @override
  State<CameraFilterCarousel> createState() => _CameraFilterCarouselState();
}

class _CameraFilterCarouselState extends State<CameraFilterCarousel> {
  bool _showSliders = false;
  bool _prefsSaved = false;

  Future<void> _savePrefs(String filterId) async {
    try {
      await ApiService.put('/profile/camera-prefs', data: {
        'filter': filterId,
        'beauty_level': widget.beautyLevel.round(),
        'brightness': widget.brightness.round(),
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 64.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            itemCount: CameraFilters.all.length + 1,
            itemBuilder: (context, index) {
              if (index == CameraFilters.all.length) {
                return Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: IconButton(
                    icon: Icon(Icons.tune,
                        color: _showSliders ? Colors.amber : Colors.white, size: 24.r),
                    onPressed: () => setState(() => _showSliders = !_showSliders),
                  ),
                );
              }
              final filter = CameraFilters.all[index];
              final selected = filter.id == widget.selectedId;
              return Padding(
                padding: EdgeInsets.only(right: 10.w),
                child: GestureDetector(
                  onTap: () {
                    widget.onFilterChanged(filter.id);
                    if (!_prefsSaved) {
                      _prefsSaved = true;
                      _savePrefs(filter.id);
                    }
                  },
                  child: Column(children: [
                    Container(
                      width: 40.r,
                      height: 40.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? Colors.amber : Colors.white30, width: 2.r),
                        gradient: LinearGradient(colors: [
                          HSLColor.fromAHSL(1, (index * 36) % 360, .55, .55).toColor(),
                          HSLColor.fromAHSL(1, (index * 36 + 60) % 360, .55, .45).toColor(),
                        ]),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(filter.label,
                        style: TextStyle(fontSize: 10.sp, color: Colors.white)),
                  ]),
                ),
              );
            },
          ),
        ),
        if (_showSliders)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(children: [
              Row(children: [
                Text('Beauty', style: TextStyle(color: Colors.white, fontSize: 11.sp)),
                Expanded(child:
                  Slider(value: widget.beautyLevel, max: 100,
                    onChanged: widget.onBeautyChanged)),
              ]),
              Row(children: [
                Text('Light', style: TextStyle(color: Colors.white, fontSize: 11.sp)),
                Expanded(child:
                  Slider(value: widget.brightness, min: -50, max: 50,
                    onChanged: widget.onBrightnessChanged)),
              ]),
            ]),
          ),
      ]),
    );
  }
}

/// Applies the current filter + brightness overlay to any preview widget.
class FilteredPreview extends StatelessWidget {
  const FilteredPreview({
    super.key,
    required this.child,
    required this.filterId,
    required this.brightness,
  });

  final Widget child;
  final String filterId;
  final double brightness;

  @override
  Widget build(BuildContext context) {
    final filter = CameraFilters.byId(filterId);
    Widget result = filter.apply(child);
    if (brightness != 0) {
      result = Stack(fit: StackFit.expand, children: [
        result,
        IgnorePointer(
          child: ColoredBox(
            color: Colors.white.withValues(alpha: (brightness.abs() / 300).clamp(0.0, 1.0)),
          ),
        ),
      ]);
    }
    return result;
  }
}
