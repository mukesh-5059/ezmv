import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/utils/tv_memory.dart';
import 'package:tv_app/widgets/tv_focus_button.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';
import 'package:tv_app/widgets/tv_pill_chip.dart';
import 'package:tv_app/widgets/tv_shortcuts.dart';
import 'package:tv_app/widgets/tv_unified_header_strip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TVTheme Design Tokens & Focus Decoration', () {
    test('Palette colors match DESIGN.md specifications exactly', () {
      expect(TVTheme.background, const Color(0xFF07080B));
      expect(TVTheme.surface, const Color(0xFF131418));
      expect(TVTheme.surfaceElevated, const Color(0xFF1C1D24));
      expect(TVTheme.primary, const Color(0xFFE50914));
      expect(TVTheme.accent, const Color(0xFFE50914));
      expect(TVTheme.accentGlow, const Color(0xFFFF3B30));
      expect(TVTheme.textPrimary, const Color(0xFFFFFFFF));
      expect(TVTheme.textSecondary, const Color(0xFF9E9EA7));
      expect(TVTheme.textMuted, const Color(0xFF8E92A2));
    });

    test('Shapes, overscan, and focus scales match requirements', () {
      expect(TVTheme.radiusMd, 10.0);
      expect(TVTheme.radiusFull, 9999.0);
      expect(TVTheme.overscanMargin, 48.0);
      expect(TVTheme.overscanPadding, const EdgeInsets.all(48.0));
      expect(TVTheme.focusScale, 1.08);
      expect(TVTheme.focusBorderWidth, 3.0);
    });

    test('focusDecoration builds dual-layer shadow and 3dp white border when focused', () {
      final focusedDec = TVTheme.focusDecoration(true);
      expect(focusedDec.border?.top.color, Colors.white);
      expect(focusedDec.border?.top.width, 3.0);
      expect(focusedDec.boxShadow, isNotNull);
      expect(focusedDec.boxShadow!.length, 2);
      expect(focusedDec.boxShadow![0].color, const Color(0x26FFFFFF));
      expect(focusedDec.boxShadow![1].color, const Color(0xD9000000));

      final unfocusedDec = TVTheme.focusDecoration(false);
      expect(unfocusedDec.border?.top.color, Colors.transparent);
      expect(unfocusedDec.border?.top.width, 0.0);
    });
  });

  group('TvMemory LMK Protection', () {
    test('TvMemory caps image cache to 75MB and 100 objects', () {
      initTvMemory();
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.maximumSizeBytes, 75 * 1024 * 1024);
      expect(cache.maximumSize, 100);

      TvMemory.clearMemoryCache();
      expect(cache.currentSize, 0);
    });
  });

  group('TvShortcuts Universal D-Pad Engine', () {
    test('isActivateKey recognizes all remote, keyboard, and gamepad triggers', () {
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.select), isTrue);
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.enter), isTrue);
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.numpadEnter), isTrue);
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.gameButtonA), isTrue);
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.space), isTrue);

      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.arrowDown), isFalse);
      expect(TvShortcuts.isActivateKey(LogicalKeyboardKey.escape), isFalse);
    });
  });

  group('TvFocusButton Widget', () {
    testWidgets('Renders label, gains focus, and responds to DPAD select', (tester) async {
      bool pressed = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: TvFocusButton(
                label: 'Play Now',
                icon: Icons.play_arrow_rounded,
                focusNode: focusNode,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Play Now'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      // Simulate TV remote DPAD center / Select key
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(pressed, isTrue);

      focusNode.dispose();
    });
  });

  group('TvUnifiedHeaderStrip Widget', () {
    testWidgets('Renders title and count, activates on Enter', (tester) async {
      bool showAllTriggered = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: TvUnifiedHeaderStrip(
                title: 'Tamil Comedy Hits',
                count: 42,
                focusNode: focusNode,
                onShowAll: () => showAllTriggered = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Tamil Comedy Hits'), findsOneWidget);
      expect(find.text('Show All (42)'), findsOneWidget);

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(showAllTriggered, isTrue);

      focusNode.dispose();
    });
  });

  group('TvPillChip Widget', () {
    testWidgets('Toggles visual selected state and responds to activation', (tester) async {
      bool tapped = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: TvPillChip(
                label: 'Action',
                isSelected: true,
                focusNode: focusNode,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Action'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tapped, isTrue);

      focusNode.dispose();
    });
  });

  group('TvFocusCard Widget', () {
    testWidgets('Renders fallback card, rating, progress bar, and activates', (tester) async {
      bool cardTapped = false;
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: TvFocusCard(
                posterUrl: '', // Tests fallback card
                title: 'Vikram',
                rating: 8.4,
                progress: 0.65,
                isTv: true,
                focusNode: focusNode,
                onTap: () => cardTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Vikram'), findsOneWidget);
      expect(find.text('8.4'), findsOneWidget);
      expect(find.text('TV'), findsOneWidget);

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(cardTapped, isTrue);

      focusNode.dispose();
    });
  });
}
