import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tv_shortcuts.dart';

/// Top Navigation Bar for 10-foot Android TV interface.
///
/// Features:
/// - Dashboard tabs: Tamil, English, Anime.
/// - Active dashboard indicated with primary red pill indicator.
/// - Action buttons on right: Search, Curated Lists, Settings.
/// - High-contrast TV focus scaling (1.06x) and ambient glow.
/// - D-pad Left/Right spatial traversal across tabs and action buttons.
class TvTopNavBar extends StatefulWidget {
  final String activeDashboardId;
  final ValueChanged<String> onDashboardChanged;
  final VoidCallback onSearchTap;
  final VoidCallback onCuratedListsTap;
  final VoidCallback onSettingsTap;

  const TvTopNavBar({
    super.key,
    required this.activeDashboardId,
    required this.onDashboardChanged,
    required this.onSearchTap,
    required this.onCuratedListsTap,
    required this.onSettingsTap,
  });

  @override
  State<TvTopNavBar> createState() => _TvTopNavBarState();
}

class _TvTopNavBarState extends State<TvTopNavBar> {
  static const List<Map<String, String>> _dashboards = [
    {'id': 'tamil', 'label': 'Tamil'},
    {'id': 'english', 'label': 'English'},
    {'id': 'anime', 'label': 'Anime'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin, vertical: 8),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // App Brand Logo / Title
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: TVTheme.primary,
                  borderRadius: TVTheme.borderRadiusSm,
                  boxShadow: [
                    BoxShadow(
                      color: TVTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Text(
                  'EzMV',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),

          // Dashboard Category Tabs
          ..._dashboards.map((dash) {
            final id = dash['id']!;
            final label = dash['label']!;
            final isSelected = widget.activeDashboardId == id;

            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _NavTabItem(
                label: label,
                isSelected: isSelected,
                onSelected: () => widget.onDashboardChanged(id),
              ),
            );
          }),

          const Spacer(),

          // Right-aligned Actions
          _NavIconButton(
            icon: Icons.search_rounded,
            label: 'Search',
            onTap: widget.onSearchTap,
          ),
          const SizedBox(width: 12),
          _NavIconButton(
            icon: Icons.playlist_play_rounded,
            label: 'Curated Lists',
            onTap: widget.onCuratedListsTap,
          ),
          const SizedBox(width: 12),
          _NavIconButton(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onTap: widget.onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _NavTabItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _NavTabItem({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<_NavTabItem> createState() => _NavTabItemState();
}

class _NavTabItemState extends State<_NavTabItem> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
        event,
        onActivate: widget.onSelected,
      ),
      child: GestureDetector(
        onTap: widget.onSelected,
        child: AnimatedScale(
          scale: _isFocused ? TVTheme.buttonFocusScale : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: AnimatedContainer(
            duration: TVTheme.focusDuration,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: _isFocused
                  ? TVTheme.surfaceElevated
                  : (widget.isSelected
                      ? TVTheme.primary.withValues(alpha: 0.18)
                      : Colors.transparent),
              borderRadius: TVTheme.borderRadiusMd,
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : (widget.isSelected ? TVTheme.primary : Colors.transparent),
                width: _isFocused ? TVTheme.focusBorderWidth : 1.5,
              ),
              boxShadow: _isFocused ? TVTheme.focusShadows : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: widget.isSelected || _isFocused ? FontWeight.w700 : FontWeight.w500,
                    color: widget.isSelected || _isFocused
                        ? TVTheme.textPrimary
                        : TVTheme.textSecondary,
                  ),
                ),
                if (widget.isSelected) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 20,
                    height: 3,
                    decoration: BoxDecoration(
                      color: TVTheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_NavIconButton> createState() => _NavIconButtonState();
}

class _NavIconButtonState extends State<_NavIconButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) => TvShortcuts.handleKeyEvent(
        event,
        onActivate: widget.onTap,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? TVTheme.buttonFocusScale : 1.0,
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          child: AnimatedContainer(
            duration: TVTheme.focusDuration,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _isFocused ? TVTheme.surfaceElevated : TVTheme.surface.withValues(alpha: 0.5),
              borderRadius: TVTheme.borderRadiusMd,
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.transparent,
                width: TVTheme.focusBorderWidth,
              ),
              boxShadow: _isFocused ? TVTheme.focusShadows : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: _isFocused ? TVTheme.textPrimary : TVTheme.textSecondary,
                ),
                if (_isFocused) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: TVTheme.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
