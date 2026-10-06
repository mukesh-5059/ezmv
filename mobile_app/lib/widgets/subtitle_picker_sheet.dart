import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';

class SubtitlePickerResult {
  final bool isOff;
  final SubtitleTrackInfo? track;

  const SubtitlePickerResult._({this.isOff = false, this.track});

  factory SubtitlePickerResult.off() => const SubtitlePickerResult._(isOff: true);
  factory SubtitlePickerResult.selected(SubtitleTrackInfo track) => SubtitlePickerResult._(track: track);
}

class SubtitlePickerSheet extends StatefulWidget {
  final List<SubtitleTrackInfo> subtitles;
  final SubtitleTrackInfo? selectedSubtitle;
  final bool isLoading;
  final double initialFontSize;
  final double initialDelaySeconds;
  final ValueChanged<double>? onFontSizeChanged;
  final ValueChanged<double>? onDelayChanged;

  const SubtitlePickerSheet({
    super.key,
    required this.subtitles,
    this.selectedSubtitle,
    this.isLoading = false,
    this.initialFontSize = 24.0,
    this.initialDelaySeconds = 0.0,
    this.onFontSizeChanged,
    this.onDelayChanged,
  });

  static Future<SubtitlePickerResult?> show({
    required BuildContext context,
    required List<SubtitleTrackInfo> subtitles,
    SubtitleTrackInfo? selectedSubtitle,
    bool isLoading = false,
    double initialFontSize = 24.0,
    double initialDelaySeconds = 0.0,
    ValueChanged<double>? onFontSizeChanged,
    ValueChanged<double>? onDelayChanged,
  }) {
    return showModalBottomSheet<SubtitlePickerResult?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SubtitlePickerSheet(
        subtitles: subtitles,
        selectedSubtitle: selectedSubtitle,
        isLoading: isLoading,
        initialFontSize: initialFontSize,
        initialDelaySeconds: initialDelaySeconds,
        onFontSizeChanged: onFontSizeChanged,
        onDelayChanged: onDelayChanged,
      ),
    );
  }

  @override
  State<SubtitlePickerSheet> createState() => _SubtitlePickerSheetState();
}

class _SubtitlePickerSheetState extends State<SubtitlePickerSheet> {
  late double _fontSize;
  late double _delay;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize;
    _delay = widget.initialDelaySeconds;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.subtitles.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) || s.language.toLowerCase().contains(q);
    }).toList();

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: isLandscape
              ? MediaQuery.of(context).size.height * 0.94
              : MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: MobileTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                const Icon(Icons.subtitles_rounded, color: MobileTheme.accent, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Subtitles & Captions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                if (widget.isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),
          // Search & Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search language (e.g. English, Tamil, Spanish)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                isDense: true,
                filled: true,
                fillColor: MobileTheme.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Options List
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              children: [
                // "Off" Tile
                Material(
                  color: widget.selectedSubtitle == null ? MobileTheme.surfaceElevated : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    leading: const Icon(Icons.subtitles_off_outlined, color: Colors.white70),
                    title: const Text('Off (Subtitles Disabled)', style: TextStyle(color: Colors.white, fontSize: 14)),
                    trailing: widget.selectedSubtitle == null
                        ? const Icon(Icons.check_circle_rounded, color: MobileTheme.accent, size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, SubtitlePickerResult.off()),
                  ),
                ),
                const SizedBox(height: 6),
                ...filtered.map((sub) {
                  final isSelected = widget.selectedSubtitle?.url == sub.url &&
                      widget.selectedSubtitle?.name == sub.name;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Material(
                      color: isSelected ? MobileTheme.surfaceElevated : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        leading: Icon(
                          sub.isExternal ? Icons.cloud_download_outlined : Icons.subtitles_rounded,
                          color: isSelected ? MobileTheme.accent : Colors.white60,
                        ),
                        title: Text(
                          sub.name,
                          style: TextStyle(
                            color: isSelected ? MobileTheme.accent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${sub.language.toUpperCase()} • ${sub.isExternal ? "OpenSubtitles" : "Embedded"}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded, color: MobileTheme.accent, size: 20)
                            : null,
                        onTap: () => Navigator.pop(context, SubtitlePickerResult.selected(sub)),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Controls (Font Size & Delay)
          Container(
            padding: EdgeInsets.fromLTRB(
              18,
              isLandscape ? 6 : 12,
              18,
              isLandscape ? 8 : (14 + MediaQuery.of(context).viewPadding.bottom),
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F12),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtitle Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_fontSize.toInt()} px', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                SizedBox(
                  height: isLandscape ? 30 : 38,
                  child: Slider(
                    value: _fontSize,
                    min: 16.0,
                    max: 48.0,
                    activeColor: MobileTheme.accent,
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      setState(() => _fontSize = val);
                      widget.onFontSizeChanged?.call(val);
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sync Offset (Delay)', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_delay >= 0 ? "+" : ""}${_delay.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                SizedBox(
                  height: isLandscape ? 30 : 38,
                  child: Slider(
                    value: _delay,
                    min: -10.0,
                    max: 10.0,
                    divisions: 40,
                    activeColor: MobileTheme.accent,
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      setState(() => _delay = val);
                      widget.onDelayChanged?.call(val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
