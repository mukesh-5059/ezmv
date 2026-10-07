import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ApiClient.init();
  runApp(const EzMVMobileApp());
}

class EzMVMobileApp extends StatelessWidget {
  const EzMVMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzMV',
      theme: MobileTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const MobileRootScreen(),
    );
  }
}

class MobileRootScreen extends StatefulWidget {
  const MobileRootScreen({super.key});

  @override
  State<MobileRootScreen> createState() => _MobileRootScreenState();
}

class _MobileRootScreenState extends State<MobileRootScreen> {
  int _currentIndex = 0;
  final GlobalKey<SettingsScreenState> _settingsKey = GlobalKey<SettingsScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const SearchScreen(),
      const LibraryScreen(),
      SettingsScreen(key: _settingsKey),
    ];
  }

  void _onTabSelected(int index) {
    if (index == 3) {
      _settingsKey.currentState?.loadCacheInfo();
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: MobileTheme.surface,
          border: Border(
            top: BorderSide(color: Colors.white10, width: 0.8),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home_filled, 'Home'),
                _buildNavItem(1, Icons.search_outlined, Icons.search, 'Search'),
                _buildNavItem(2, Icons.video_library_outlined, Icons.video_library_rounded, 'Library'),
                _buildNavItem(3, Icons.settings_outlined, Icons.settings, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: Center(
        child: InkResponse(
          onTap: () => _onTabSelected(index),
          radius: 26,
          containedInkWell: false,
          highlightShape: BoxShape.circle,
          splashFactory: InkRipple.splashFactory,
          splashColor: MobileTheme.accent.withValues(alpha: 0.3),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 22,
                  color: isSelected ? MobileTheme.accent : MobileTheme.textMuted,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? MobileTheme.accent : MobileTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
