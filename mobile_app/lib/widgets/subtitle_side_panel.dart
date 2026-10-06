import 'dart:math';
import 'dart:ui';
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

class SubtitleSidePanel extends StatefulWidget {
  final List<SubtitleTrackInfo> subtitles;
  final SubtitleTrackInfo? selectedSubtitle;
  final bool isLoading;

  const SubtitleSidePanel({
    super.key,
    required this.subtitles,
    this.selectedSubtitle,
    this.isLoading = false,
  });

  static Future<SubtitlePickerResult?> show({
    required BuildContext context,
    required List<SubtitleTrackInfo> subtitles,
    SubtitleTrackInfo? selectedSubtitle,
    bool isLoading = false,
  }) {
    return showGeneralDialog<SubtitlePickerResult?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Subtitles Panel',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: SubtitleSidePanel(
            subtitles: subtitles,
            selectedSubtitle: selectedSubtitle,
            isLoading: isLoading,
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        );
      },
    );
  }

  @override
  State<SubtitleSidePanel> createState() => _SubtitleSidePanelState();
}

class _SubtitleSidePanelState extends State<SubtitleSidePanel> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = min(380.0, screenWidth * 0.88);
    final isOffSelected = widget.selectedSubtitle == null;

    final filtered = widget.subtitles.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) || s.language.toLowerCase().contains(q);
    }).toList();

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: panelWidth,
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF101014).withValues(alpha: 0.95),
              border: const Border(
                left: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: SafeArea(
              left: false,
              child: Column(
                children: [
                  // Top Panel Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.subtitles_rounded, color: MobileTheme.accent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Subtitles',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Search Filter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filter language or provider...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitles List
                  Expanded(
                    child: widget.isLoading && widget.subtitles.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                                ),
                                SizedBox(height: 12),
                                Text('Fetching subtitles...', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              ],
                            ),
                          )
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            children: [
                              // Off option
                              _buildOptionTile(
                                title: 'Off (Subtitles Disabled)',
                                subtitle: 'No caption track',
                                isSelected: isOffSelected,
                                onTap: () => Navigator.pop(context, SubtitlePickerResult.off()),
                              ),
                              const Divider(color: Colors.white10, height: 16),

                              if (filtered.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 30),
                                  child: Center(
                                    child: Text(
                                      'No matching subtitles found.',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  ),
                                )
                              else
                                ...filtered.map((sub) {
                                  final isSelected = widget.selectedSubtitle?.url == sub.url &&
                                      widget.selectedSubtitle?.name == sub.name;
                                  return _buildOptionTile(
                                    title: sub.name,
                                    subtitle: '${sub.language.toUpperCase()} • ${sub.isExternal ? "OpenSubtitles" : "Embedded"}',
                                    isSelected: isSelected,
                                    badge: sub.language.toUpperCase(),
                                    onTap: () => Navigator.pop(context, SubtitlePickerResult.selected(sub)),
                                  );
                                }),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    String? badge,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isSelected ? MobileTheme.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? MobileTheme.accent.withValues(alpha: 0.6) : Colors.transparent,
          width: 1,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isSelected ? Colors.white70 : Colors.white38,
            fontSize: 11,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: MobileTheme.accent, size: 18)
            : (badge != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                : null),
        onTap: onTap,
      ),
    );
  }
}
