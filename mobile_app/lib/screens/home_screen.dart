import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/actor_lane.dart';
import '../widgets/movie_lane.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  String? _errorMessage;

  String _selectedLanguage = 'ta'; // 'ta' (Tamil) or 'en' (English)

  List<DashboardLane> _lanes = [];
  List<Actor> _curatedActors = [];
  final Set<String> _loadingLaneIds = {};

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
      final actors = _selectedLanguage == 'ta'
          ? await ApiClient.getCuratedActors(language: 'ta')
          : <Actor>[];

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

  Future<void> _loadMoreLane(DashboardLane lane) async {
    if (_loadingLaneIds.contains(lane.id) || !lane.hasMore || lane.nextPage == null) return;
    setState(() => _loadingLaneIds.add(lane.id));

    final res = await ApiClient.getDashboardLane(
      laneId: lane.id,
      language: _selectedLanguage.isNotEmpty ? _selectedLanguage : 'ta',
      page: lane.nextPage!,
    );

    if (mounted) {
      setState(() {
        _loadingLaneIds.remove(lane.id);
        if (res != null) {
          final rawItems = res['items'] as List? ?? [];
          final newMovies = rawItems.map((e) => Movie.fromJson(e)).toList();
          if (newMovies.isNotEmpty) {
            lane.items.addAll(newMovies);
            lane.hasMore = res['has_more'] ?? false;
            lane.nextPage = res['next_page'];
          } else {
            lane.hasMore = false;
            lane.nextPage = null;
          }
        }
      });
    }
  }

  void _onLanguageSelected(String code) {
    if (_selectedLanguage == code) return;
    setState(() => _selectedLanguage = code);
    _loadDashboardData();
  }

  Widget _buildLanguageToggleItem(String label, String code) {
    final isSelected = _selectedLanguage == code;
    return GestureDetector(
      onTap: () => _onLanguageSelected(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? MobileTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
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
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: MobileTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLanguageToggleItem('Tamil', 'ta'),
                _buildLanguageToggleItem('English', 'en'),
              ],
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: MobileTheme.accent));
    }
    if (_errorMessage != null) {
      return Center(
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
      );
    }

    if (_lanes.isEmpty && _curatedActors.isEmpty) {
      return RefreshIndicator(
        color: MobileTheme.accent,
        backgroundColor: MobileTheme.surfaceElevated,
        onRefresh: _loadDashboardData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            _buildEmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
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
                title: 'Featured Cast & Creators',
                actors: _curatedActors,
              ),
            ),
          ..._lanes.map((lane) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: MovieLane(
                title: lane.title,
                movies: lane.items,
                hasMore: lane.hasMore,
                isLoadingMore: _loadingLaneIds.contains(lane.id),
                onLoadMore: () => _loadMoreLane(lane),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (ApiClient.isServerlessMode && _selectedLanguage == 'en' && !ApiClient.hasTraktKey) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MobileTheme.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.list_alt_rounded, color: MobileTheme.accent, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Trakt API Key Required',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'English curated lists, trending, and box office discovery require a Trakt Client ID in Self-Serving mode.\n\nPlease configure your Trakt Client ID in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MobileTheme.surfaceElevated,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Colors.white12),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18, color: MobileTheme.accent),
                label: const Text('Reload / Check Key'),
                onPressed: _loadDashboardData,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_outlined, color: Colors.white30, size: 54),
            const SizedBox(height: 12),
            const Text(
              'No titles found',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Unable to load movies for this category.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: MobileTheme.surfaceElevated,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.white12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18, color: MobileTheme.accent),
              label: const Text('Reload'),
              onPressed: _loadDashboardData,
            ),
          ],
        ),
      ),
    );
  }
}
