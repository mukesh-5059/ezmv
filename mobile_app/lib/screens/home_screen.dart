import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/actor_lane.dart';
import '../widgets/movie_lane.dart';
import '../widgets/settings_sheet.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedLanguage = 'ta'; // default to Tamil or ''
  final List<Map<String, String>> _languages = [
    {'code': 'ta', 'label': 'Tamil'},
    {'code': 'en', 'label': 'English'},
    {'code': 'te', 'label': 'Telugu'},
    {'code': 'hi', 'label': 'Hindi'},
    {'code': 'ml', 'label': 'Malayalam'},
    {'code': 'kn', 'label': 'Kannada'},
    {'code': '', 'label': 'All'},
  ];

  List<DashboardLane> _lanes = [];
  List<Actor> _curatedActors = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dashboard = await ApiClient.getDashboard(language: _selectedLanguage);
      final actors = await ApiClient.getCuratedActors(language: _selectedLanguage.isNotEmpty ? _selectedLanguage : 'ta');

      if (mounted) {
        setState(() {
          _lanes = dashboard;
          _curatedActors = actors;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load dashboard: $e';
        });
      }
    }
  }

  void _onLanguageSelected(String code) {
    if (_selectedLanguage == code) return;
    setState(() => _selectedLanguage = code);
    _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: MobileTheme.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'EZMV',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Movies & Series',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 24),
            tooltip: 'Search',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'Settings',
            onPressed: () => SettingsSheet.show(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Language Filter Tabs
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final isSelected = _selectedLanguage == lang['code'];

                return ChoiceChip(
                  label: Text(lang['label']!),
                  selected: isSelected,
                  selectedColor: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide.none,
                  onSelected: (_) => _onLanguageSelected(lang['code']!),
                );
              },
            ),
          ),
          // Content with Pull to Refresh
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
                : (_errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 48),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 16),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                              onPressed: _loadDashboardData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: MobileTheme.accent,
                        backgroundColor: MobileTheme.surfaceElevated,
                        onRefresh: _loadDashboardData,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            if (_curatedActors.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ActorLane(
                                  title: '🎭 Featured Cast & Creators',
                                  actors: _curatedActors,
                                ),
                              ),
                            ..._lanes.map((lane) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 6),
                                child: MovieLane(
                                  title: lane.title,
                                  movies: lane.items,
                                ),
                              );
                            }),
                            const SizedBox(height: 24),
                          ],
                        ),
                      )),
          ),
        ],
      ),
    );
  }
}
