import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/home/tv_actors_lane.dart';
import '../widgets/home/tv_billboard.dart';
import '../widgets/home/tv_continue_watching_lane.dart';
import '../widgets/home/tv_movie_lane.dart';
import '../widgets/home/tv_top_nav_bar.dart';
import '../widgets/tv_focus_button.dart';
import 'lane_grid_screen.dart';

/// 10-Foot Lean-Back Home Screen for Android TV.
///
/// Features:
/// - Manages active dashboard tabs: Tamil (default), English, Anime.
/// - Loads dashboard lanes via [ApiClient.instance.getDashboard].
/// - Vertical layout assembling:
///   1. [TvTopNavBar]
///   2. [TvBillboard] (Hero carousel with auto-scroll heuristic)
///   3. [TvContinueWatchingLane] (Row 0, dynamic hide if empty)
///   4. Content Lanes via [TvMovieLane]
///   5. [TvActorsLane] (Tamil dashboard only bottom shelf)
/// - Auto-centering vertical viewport alignment on D-pad navigation.
/// - Remote Back hierarchy:
///   - Scrolled deep -> smooth-scrolls up to Billboard.
///   - At top -> double-back exit confirmation toast.
/// - Offline / error state with retry action.
class HomeScreen extends StatefulWidget {
  final void Function(MovieSummary movie)? onDetailsTap;
  final void Function(MovieSummary movie)? onPlayTap;
  final void Function(ActorSummary actor)? onActorTap;
  final void Function(DashboardLane lane)? onShowAllLane;
  final VoidCallback? onSearchTap;
  final VoidCallback? onSettingsTap;

  const HomeScreen({
    super.key,
    this.onDetailsTap,
    this.onPlayTap,
    this.onActorTap,
    this.onShowAllLane,
    this.onSearchTap,
    this.onSettingsTap,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activeDashboardId = 'tamil';
  Dashboard? _dashboard;
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _verticalScrollController = ScrollController();
  final GlobalKey<TvContinueWatchingLaneState> _continueWatchingKey = GlobalKey();

  final FocusNode _navActiveTabFocusNode = FocusNode(debugLabel: 'NavActiveTab');
  final FocusNode _navSearchFocusNode = FocusNode(debugLabel: 'NavSearch');
  final FocusNode _billboardPlayFocusNode = FocusNode(debugLabel: 'BillboardPlay');
  final FocusNode _billboardDetailsFocusNode = FocusNode(debugLabel: 'BillboardDetails');
  final FocusNode _continueWatchingHeaderNode = FocusNode(debugLabel: 'CWHeader');
  final FocusNode _actorsHeaderNode = FocusNode(debugLabel: 'ActorsHeader');
  final Map<String, FocusNode> _laneHeaderNodes = {};

  FocusNode _getLaneHeaderNode(String laneId) =>
      _laneHeaderNodes.putIfAbsent(laneId, () => FocusNode(debugLabel: 'LaneHeader_$laneId'));

  bool _isScrolledDown = false;
  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    _verticalScrollController.addListener(_onVerticalScroll);
    _loadDashboard();
  }

  @override
  void dispose() {
    _verticalScrollController.removeListener(_onVerticalScroll);
    _verticalScrollController.dispose();
    _navActiveTabFocusNode.dispose();
    _navSearchFocusNode.dispose();
    _billboardPlayFocusNode.dispose();
    _billboardDetailsFocusNode.dispose();
    _continueWatchingHeaderNode.dispose();
    _actorsHeaderNode.dispose();
    for (final node in _laneHeaderNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onVerticalScroll() {
    if (!_verticalScrollController.hasClients) return;
    final scrolled = _verticalScrollController.offset > 320;
    if (scrolled != _isScrolledDown) {
      setState(() => _isScrolledDown = scrolled);
    }
  }

  Future<void> _loadDashboard({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dash = await ApiClient.instance.getDashboard(
        _activeDashboardId,
        refresh: refresh,
      );
      if (mounted) {
        setState(() {
          _dashboard = dash;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Unable to load catalog from server. Please check your network or server configuration.';
          _isLoading = false;
        });
      }
    }
  }

  void _onDashboardChanged(String id) {
    if (_activeDashboardId == id) return;
    setState(() {
      _activeDashboardId = id;
    });
    _loadDashboard();
  }

  void _scrollToTop() {
    if (_verticalScrollController.hasClients && _verticalScrollController.offset > 0) {
      _verticalScrollController.jumpTo(0);
    }
  }

  void _focusFirstLaneHeader() {
    final lanes = _dashboard?.lanes ?? [];
    if (_continueWatchingKey.currentState?.hasEntries == true) {
      _continueWatchingHeaderNode.requestFocus();
    } else if (lanes.isNotEmpty) {
      _getLaneHeaderNode(lanes.first.id).requestFocus();
    }
  }

  void _ensureFocusedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null) {
        final ro = focusedContext.findRenderObject();
        if (ro != null && ro.attached) {
          Scrollable.maybeOf(focusedContext, axis: Axis.vertical)?.position.ensureVisible(
            ro,
            alignment: 0.22,
            duration: Duration.zero,
          );
        }
      }
    });
  }

  void _handleBackPress() {
    if (_verticalScrollController.hasClients && _verticalScrollController.offset > 240) {
      _scrollToTop();
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Press Back again to exit',
            style: TextStyle(color: TVTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: TVTheme.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: TVTheme.borderRadiusMd),
          margin: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _handlePlayMovie(MovieSummary movie) async {
    if (widget.onPlayTap != null) {
      widget.onPlayTap!(movie);
      return;
    }

    try {
      final streams = await ApiClient.instance.getStreams(movie.mediaType, movie.imdbId);
      if (!mounted) return;

      if (streams.isNotEmpty) {
        final topStream = streams.first;
        Navigator.pushNamed(
          context,
          '/player',
          arguments: {
            'streamUrl': topStream.url,
            'movieTitle': movie.title,
            'tmdbId': movie.tmdbId ?? 0,
            'mediaType': movie.mediaType,
            'quality': topStream.quality,
            'provider': topStream.provider,
          },
        );
      } else {
        _navigateToDetails(movie);
      }
    } catch (_) {
      if (mounted) _navigateToDetails(movie);
    }
  }

  Future<void> _handleResumeWatching(ContinueWatchingEntry entry) async {
    try {
      final streams = await ApiClient.instance.getStreams(
        entry.mediaType,
        entry.imdbId,
        season: entry.season,
        episode: entry.episode,
      );
      if (!mounted) return;

      if (streams.isNotEmpty) {
        final topStream = streams.first;
        Navigator.pushNamed(
          context,
          '/player',
          arguments: {
            'streamUrl': topStream.url,
            'movieTitle': entry.title,
            'tmdbId': 0,
            'mediaType': entry.mediaType,
            'season': entry.season,
            'episode': entry.episode,
            'quality': topStream.quality,
            'provider': topStream.provider,
            'initialPositionSeconds': entry.positionMs ~/ 1000,
          },
        );
      }
    } catch (_) {}
  }

  void _navigateToDetails(MovieSummary movie) async {
    if (widget.onDetailsTap != null) {
      widget.onDetailsTap!(movie);
      return;
    }
    await Navigator.pushNamed(context, '/details', arguments: movie);
    if (mounted) _ensureFocusedVisible();
  }

  void _navigateToActor(ActorSummary actor) async {
    if (widget.onActorTap != null) {
      widget.onActorTap!(actor);
      return;
    }
    await Navigator.pushNamed(context, '/actor', arguments: actor);
    if (mounted) _ensureFocusedVisible();
  }

  void _navigateToLaneGrid(DashboardLane lane) async {
    if (widget.onShowAllLane != null) {
      widget.onShowAllLane!(lane);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LaneGridScreen(
          dashboardId: _activeDashboardId,
          laneId: lane.id,
          laneTitle: lane.title,
        ),
      ),
    );
    if (mounted) _ensureFocusedVisible();
  }

  void _navigateToSearch() async {
    if (widget.onSearchTap != null) {
      widget.onSearchTap!();
      return;
    }
    await Navigator.pushNamed(context, '/search');
    if (mounted) _ensureFocusedVisible();
  }

  void _showSettings() async {
    if (widget.onSettingsTap != null) {
      widget.onSettingsTap!();
      return;
    }
    await Navigator.pushNamed(context, '/settings');
    if (mounted) _ensureFocusedVisible();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: TVTheme.background,
        body: _isLoading
            ? const Center(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: TVTheme.primary,
                  ),
                ),
              )
            : _errorMessage != null
                ? _buildErrorView()
                : _buildHomeContent(),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: TVTheme.overscanMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: TVTheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Connection Error',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: TVTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: TVTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvFocusButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  autofocus: true,
                  onPressed: () => _loadDashboard(refresh: true),
                ),
                const SizedBox(width: 16),
                TvFocusButton(
                  label: 'Settings',
                  icon: Icons.settings_rounded,
                  isPrimary: false,
                  onPressed: _showSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    final lanes = _dashboard?.lanes ?? [];

    return Stack(
      children: [
        // Scrollable content area
        ListView(
          controller: _verticalScrollController,
          padding: const EdgeInsets.only(top: 68),
          children: [
            // 1. Hero Billboard Carousel
            if (lanes.isNotEmpty)
              RepaintBoundary(
                child: TvBillboard(
                  lanes: lanes,
                  isVisible: !_isScrolledDown,
                  playButtonFocusNode: _billboardPlayFocusNode,
                  detailsButtonFocusNode: _billboardDetailsFocusNode,
                  onPlay: _handlePlayMovie,
                  onDetails: _navigateToDetails,
                  onNavigateUp: () {
                    _scrollToTop();
                    _navActiveTabFocusNode.requestFocus();
                  },
                  onNavigateDown: _focusFirstLaneHeader,
                ),
              ),

            // 2. Row 0: Continue Watching Lane (Dynamic)
            RepaintBoundary(
              child: TvContinueWatchingLane(
                key: _continueWatchingKey,
                headerFocusNode: _continueWatchingHeaderNode,
                onResume: _handleResumeWatching,
                onNavigateUpFromHeader: () {
                  _scrollToTop();
                  _billboardPlayFocusNode.requestFocus();
                },
                onNavigateDownFromCard: () {
                  if (lanes.isNotEmpty) {
                    _getLaneHeaderNode(lanes.first.id).requestFocus();
                  }
                },
              ),
            ),

            // 3. Content Lanes
            ...lanes.asMap().entries.map((entry) {
              final i = entry.key;
              final lane = entry.value;
              return RepaintBoundary(
                key: ValueKey('lane_${lane.id}'),
                child: TvMovieLane(
                  lane: lane,
                  headerFocusNode: _getLaneHeaderNode(lane.id),
                  onMovieTap: _navigateToDetails,
                  onShowAll: _navigateToLaneGrid,
                  onNavigateUpFromHeader: () {
                    if (i == 0) {
                      if (_continueWatchingKey.currentState?.hasEntries == true) {
                        _continueWatchingHeaderNode.requestFocus();
                      } else {
                        _scrollToTop();
                        _billboardPlayFocusNode.requestFocus();
                      }
                    } else {
                      _getLaneHeaderNode(lanes[i - 1].id).requestFocus();
                    }
                  },
                  onNavigateDownFromCard: () {
                    if (i < lanes.length - 1) {
                      _getLaneHeaderNode(lanes[i + 1].id).requestFocus();
                    } else if (_activeDashboardId == 'tamil') {
                      _actorsHeaderNode.requestFocus();
                    }
                  },
                ),
              );
            }),

            // 4. Tamil Actors Lane (Tamil Dashboard Only Shelf)
            if (_activeDashboardId == 'tamil')
              TvActorsLane(
                headerFocusNode: _actorsHeaderNode,
                onActorTap: _navigateToActor,
                onNavigateUpFromHeader: () {
                  if (lanes.isNotEmpty) {
                    _getLaneHeaderNode(lanes.last.id).requestFocus();
                  }
                },
              ),

            const SizedBox(height: 48),
          ],
        ),

        // Pinned Top Navigation Bar with subtle scrim backdrop
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  TVTheme.background.withValues(alpha: 0.95),
                  TVTheme.background.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
            child: TvTopNavBar(
              activeDashboardId: _activeDashboardId,
              activeTabFocusNode: _navActiveTabFocusNode,
              searchButtonFocusNode: _navSearchFocusNode,
              onDashboardChanged: _onDashboardChanged,
              onSearchTap: _navigateToSearch,
              onCuratedListsTap: _navigateToSearch,
              onSettingsTap: _showSettings,
              onNavigateDown: () {
                _scrollToTop();
                if (lanes.isNotEmpty) {
                  _billboardPlayFocusNode.requestFocus();
                } else {
                  _focusFirstLaneHeader();
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
