import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

class SubtitleSettingsSidePanel extends StatefulWidget {
  final double initialFontSize;
  final double initialDelaySeconds;
  final ValueChanged<double>? onFontSizeChanged;
  final ValueChanged<double>? onDelayChanged;

  const SubtitleSettingsSidePanel({
    super.key,
    required this.initialFontSize,
    required this.initialDelaySeconds,
    this.onFontSizeChanged,
    this.onDelayChanged,
  });

  static Future<void> show({
    required BuildContext context,
    required double initialFontSize,
    required double initialDelaySeconds,
    ValueChanged<double>? onFontSizeChanged,
    ValueChanged<double>? onDelayChanged,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Subtitle Settings Panel',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: SubtitleSettingsSidePanel(
            initialFontSize: initialFontSize,
            initialDelaySeconds: initialDelaySeconds,
            onFontSizeChanged: onFontSizeChanged,
            onDelayChanged: onDelayChanged,
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
  State<SubtitleSettingsSidePanel> createState() => _SubtitleSettingsSidePanelState();
}

class _SubtitleSettingsSidePanelState extends State<SubtitleSettingsSidePanel> {
  late double _fontSize;
  late double _delay;

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize;
    _delay = widget.initialDelaySeconds;
  }

  void _updateFontSize(double size) {
    setState(() => _fontSize = size);
    widget.onFontSizeChanged?.call(size);
  }

  void _updateDelay(double delay) {
    final clamped = (delay * 10).round() / 10.0;
    setState(() => _delay = clamped.clamp(-10.0, 10.0));
    widget.onDelayChanged?.call(_delay);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = min(360.0, screenWidth * 0.85);

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: MobileTheme.accent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Subtitle Settings',
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
                  const Divider(color: Colors.white10, height: 1),

                  Expanded(
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Font Size Section
                        _buildSectionHeader('Font Size', '${_fontSize.toInt()} px'),
                        const SizedBox(height: 8),
                        Slider(
                          value: _fontSize.clamp(16.0, 48.0),
                          min: 16.0,
                          max: 48.0,
                          activeColor: MobileTheme.accent,
                          inactiveColor: Colors.white12,
                          onChanged: _updateFontSize,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildPresetButton('Small', 18.0, _fontSize == 18.0),
                            _buildPresetButton('Default', 24.0, _fontSize == 24.0),
                            _buildPresetButton('Large', 32.0, _fontSize == 32.0),
                            _buildPresetButton('Huge', 42.0, _fontSize == 42.0),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // Subtitle Delay Section
                        _buildSectionHeader(
                          'Sync Offset (Delay)',
                          '${_delay >= 0 ? "+" : ""}${_delay.toStringAsFixed(1)}s',
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: _delay.clamp(-10.0, 10.0),
                          min: -10.0,
                          max: 10.0,
                          divisions: 40,
                          activeColor: MobileTheme.accent,
                          inactiveColor: Colors.white12,
                          onChanged: _updateDelay,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildNudgeButton('-1.0s', () => _updateDelay(_delay - 1.0)),
                            _buildNudgeButton('-0.5s', () => _updateDelay(_delay - 0.5)),
                            _buildResetButton(),
                            _buildNudgeButton('+0.5s', () => _updateDelay(_delay + 0.5)),
                            _buildNudgeButton('+1.0s', () => _updateDelay(_delay + 1.0)),
                          ],
                        ),
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

  Widget _buildSectionHeader(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: MobileTheme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: MobileTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetButton(String label, double size, bool isSelected) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: () => _updateFontSize(size),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? MobileTheme.accent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? MobileTheme.accent : Colors.white10,
                width: 1,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNudgeButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildResetButton() {
    return InkWell(
      onTap: () => _updateDelay(0.0),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _delay != 0.0
              ? MobileTheme.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _delay != 0.0 ? MobileTheme.accent.withValues(alpha: 0.5) : Colors.white10,
            width: 1,
          ),
        ),
        child: Text(
          'Reset',
          style: TextStyle(
            color: _delay != 0.0 ? Colors.white : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
