import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_pill_chip.dart';
import '../widgets/tv_shortcuts.dart';

enum FilterDimension {
  type,
  genre,
  year,
  rating,
  sort,
}

/// 10-Foot TV Lane Grid & Filter Screen.
///
/// Features:
/// - 2-Area Layout: Left 70% 5-column virtualized movie grid, Right 30% vertical filter strip.
/// - Full-width movie grid when no filter strip is active.
/// - Top Bar: Back button, Lane Title (24sp bold), Clear Filters button.
/// - Filter Pills Row: Type, Genre, Year, Rating, Sort By.
/// - Right-Anchored Filter Strip with auto-focus to active selection, checkmark, and D-pad dismissal.
/// - 100-item page virtualization with lookahead prefetch (at items.length - 15).
/// - Skeletons during loading (`canRequestFocus: false`).
/// - "End of Catalog" banner when hasMore == false.
/// - PageStorageKey preserving scroll offset during navigation.
/// - Remote Back key hierarchy: strip open -> close strip; scrolled -> scroll to row 0; at row 0 -> pop screen.
class LaneGridScreen extends StatefulWidget {
  final String dashboardId;
  final String laneId;
  final String laneTitle;
  final ApiClient? apiClient;
  final void Function(MovieSummary movie)? onMovieSelected;

  const LaneGridScreen({
    super.key,
    required this.dashboardId,
    required this.laneId,
    required this.laneTitle,
    this.apiClient,
    this.onMovieSelected,
  });

  @override
  State<LaneGridScreen> createState() => _LaneGridScreenState();
}

class _LaneGridScreenState extends State<LaneGridScreen> {
  late final ApiClient _apiClient;
  late final ScrollController _scrollController;

  // Header & Filter FocusNodes
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _clearFiltersFocusNode = FocusNode();
  final FocusNode _typePillFocusNode = FocusNode();
  final FocusNode _genrePillFocusNode = FocusNode();
  final FocusNode _yearPillFocusNode = FocusNode();
  final FocusNode _ratingPillFocusNode = FocusNode();
  final FocusNode _sortPillFocusNode = FocusNode();

  FocusNode? _lastFocusedPillNode;

  // Filter selections
  String _selectedType = 'All';
  String _selectedGenre = 'All';
  String _selectedYear = 'All';
  String _selectedRating = 'All';
  String _selectedSort = 'Popular';

  // Active filter dimension strip
  FilterDimension? _activeFilterDimension;

  // Data & Pagination state
  final List<MovieSummary> _items = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  String? _errorMessage;

  static const List<String> _typeOptions = ['All', 'Movies', 'TV'];

  static const List<String> _genreOptions = [
    'All',
    'Action',
    'Adventure',
    'Animation',
    'Anime',
    'Biography',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Sci-Fi',
    'Sports',
    'Thriller',
    'War',
  ];

  static const List<String> _yearOptions = [
    'All',
    '2024',
    '2023',
    '2022',
    '2020s',
    '2010s',
    '2000s',
    '90s',
    'classic',
  ];

  static const List<String> _ratingOptions = [
    'All',
    '9.0+',
    '8.0+',
    '7.0+',
    '6.0+',
  ];

  static const List<String> _sortOptions = [
    'Popular',
    'Top Rated',
    'Newest',
    'Oldest',
    'Title',
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _scrollController = ScrollController();
    _fetchLane(page: 1, reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _backButtonFocusNode.dispose();
    _clearFiltersFocusNode.dispose();
    _typePillFocusNode.dispose();
    _genrePillFocusNode.dispose();
    _yearPillFocusNode.dispose();
    _ratingPillFocusNode.dispose();
    _sortPillFocusNode.dispose();
    super.dispose();
  }

  String? _mapTypeParam() {
    if (_selectedType == 'Movies') return 'movie';
    if (_selectedType == 'TV') return 'tv';
    return null;
  }

  String? _mapGenreParam() {
    if (_selectedGenre == 'All') return null;
    return _selectedGenre.toLowerCase();
  }

  int? _mapYearParam() {
    if (_selectedYear == 'All') return null;
    if (_selectedYear == '2020s') return 2020;
    if (_selectedYear == '2010s') return 2010;
    if (_selectedYear == '2000s') return 2000;
    if (_selectedYear == '90s') return 1990;
    if (_selectedYear == 'classic') return 1980;
    return int.tryParse(_selectedYear);
  }

  double? _mapRatingParam() {
    if (_selectedRating == 'All') return null;
    return double.tryParse(_selectedRating.replaceAll('+', ''));
  }

  String? _mapSortParam() {
    switch (_selectedSort) {
      case 'Top Rated':
        return 'top_rated';
      case 'Newest':
        return 'newest';
      case 'Oldest':
        return 'oldest';
      case 'Title':
        return 'title';
      case 'Popular':
      default:
        return 'popular';
    }
  }

  Future<void> _fetchLane({required int page, bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _items.clear();
      });
    }

    try {
      final response = await _apiClient.getLane(
        widget.dashboardId,
        widget.laneId,
        page: page,
        type: _mapTypeParam(),
        genre: _mapGenreParam(),
        year: _mapYearParam(),
        minRating: _mapRatingParam(),
        sortBy: _mapSortParam(),
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _currentPage = response.page;
        _hasMore = response.hasMore;
        if (reset) {
          _items.clear();
        }
        _items.addAll(response.items);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchMore() async {
    if (_isFetchingMore || !_hasMore || _isLoading) return;

    setState(() => _isFetchingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final response = await _apiClient.getLane(
        widget.dashboardId,
        widget.laneId,
        page: nextPage,
        type: _mapTypeParam(),
        genre: _mapGenreParam(),
        year: _mapYearParam(),
        minRating: _mapRatingParam(),
        sortBy: _mapSortParam(),
      );

      if (!mounted) return;

      setState(() {
        _isFetchingMore = false;
        _currentPage = response.page;
        _hasMore = response.hasMore;
        _items.addAll(response.items);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFetchingMore = false);
    }
  }

  void _onCardFocused(int index) {
    if (index >= _items.length - 15 && _hasMore && !_isFetchingMore && !_isLoading) {
      _fetchMore();
    }
  }

  void _handleBack() {
    // Priority 1: Dismiss active filter strip
    if (_activeFilterDimension != null) {
      setState(() => _activeFilterDimension = null);
      _lastFocusedPillNode?.requestFocus();
      return;
    }

    // Priority 2: Smooth-scroll to Row 0 if scrolled down
    if (_scrollController.hasClients && _scrollController.offset > 20) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      _backButtonFocusNode.requestFocus();
      return;
    }

    // Priority 3: Pop screen and return to Home
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    final hasChanges = _selectedType != 'All' ||
        _selectedGenre != 'All' ||
        _selectedYear != 'All' ||
        _selectedRating != 'All' ||
        _selectedSort != 'Popular';

    if (!hasChanges && _items.isNotEmpty) return;

    setState(() {
      _selectedType = 'All';
      _selectedGenre = 'All';
      _selectedYear = 'All';
      _selectedRating = 'All';
      _selectedSort = 'Popular';
      _activeFilterDimension = null;
    });

    _fetchLane(page: 1, reset: true);
  }

  void _openFilterStrip(FilterDimension dimension, FocusNode pillNode) {
    setState(() {
      _activeFilterDimension = dimension;
      _lastFocusedPillNode = pillNode;
    });
  }

  void _closeFilterStrip() {
    setState(() => _activeFilterDimension = null);
    _lastFocusedPillNode?.requestFocus();
  }

  void _applyFilterOption(FilterDimension dimension, String option) {
    setState(() {
      switch (dimension) {
        case FilterDimension.type:
          _selectedType = option;
          break;
        case FilterDimension.genre:
          _selectedGenre = option;
          break;
        case FilterDimension.year:
          _selectedYear = option;
          break;
        case FilterDimension.rating:
          _selectedRating = option;
          break;
        case FilterDimension.sort:
          _selectedSort = option;
          break;
      }
      _activeFilterDimension = null;
    });

    _lastFocusedPillNode?.requestFocus();
    _fetchLane(page: 1, reset: true);
  }

  List<String> _getFilterStripOptions(FilterDimension dimension) {
    switch (dimension) {
      case FilterDimension.type:
        return _typeOptions;
      case FilterDimension.genre:
        return _genreOptions;
      case FilterDimension.year:
        return _yearOptions;
      case FilterDimension.rating:
        return _ratingOptions;
      case FilterDimension.sort:
        return _sortOptions;
    }
  }

  String _getFilterStripTitle(FilterDimension dimension) {
    switch (dimension) {
      case FilterDimension.type:
        return 'Media Type';
      case FilterDimension.genre:
        return 'Genre';
      case FilterDimension.year:
        return 'Release Year';
      case FilterDimension.rating:
        return 'Minimum Rating';
      case FilterDimension.sort:
        return 'Sort By';
    }
  }

  String _getCurrentFilterValue(FilterDimension dimension) {
    switch (dimension) {
      case FilterDimension.type:
        return _selectedType;
      case FilterDimension.genre:
        return _selectedGenre;
      case FilterDimension.year:
        return _selectedYear;
      case FilterDimension.rating:
        return _selectedRating;
      case FilterDimension.sort:
        return _selectedSort;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStripOpen = _activeFilterDimension != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: TVTheme.background,
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.backspace ||
                  event.logicalKey == LogicalKeyboardKey.goBack) {
                _handleBack();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 48, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(),
                const SizedBox(height: 16),
                _buildFilterPillsRow(),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Area: 5-column Movie Grid (70% when strip open, 100% when closed)
                      Expanded(
                        flex: isStripOpen ? 7 : 10,
                        child: _buildGridArea(),
                      ),
                      // Right Area: 30% Vertical Filter Strip
                      if (isStripOpen) ...[
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 3,
                          child: _buildFilterStrip(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        TvFocusButton(
          focusNode: _backButtonFocusNode,
          label: 'Back',
          icon: Icons.arrow_back_rounded,
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onPressed: _handleBack,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            widget.laneTitle,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: TVTheme.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 20),
        TvFocusButton(
          focusNode: _clearFiltersFocusNode,
          label: 'Clear Filters',
          icon: Icons.clear_rounded,
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          onPressed: _clearFilters,
        ),
      ],
    );
  }

  Widget _buildFilterPillsRow() {
    final isTypeOpen = _activeFilterDimension == FilterDimension.type;
    final isGenreOpen = _activeFilterDimension == FilterDimension.genre;
    final isYearOpen = _activeFilterDimension == FilterDimension.year;
    final isRatingOpen = _activeFilterDimension == FilterDimension.rating;
    final isSortOpen = _activeFilterDimension == FilterDimension.sort;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TvPillChip(
            focusNode: _typePillFocusNode,
            label: _selectedType == 'All' ? 'Type' : 'Type: $_selectedType',
            isSelected: _selectedType != 'All' || isTypeOpen,
            onTap: () => _openFilterStrip(FilterDimension.type, _typePillFocusNode),
          ),
          const SizedBox(width: 12),
          TvPillChip(
            focusNode: _genrePillFocusNode,
            label: _selectedGenre == 'All' ? 'Genre' : 'Genre: $_selectedGenre',
            isSelected: _selectedGenre != 'All' || isGenreOpen,
            onTap: () => _openFilterStrip(FilterDimension.genre, _genrePillFocusNode),
          ),
          const SizedBox(width: 12),
          TvPillChip(
            focusNode: _yearPillFocusNode,
            label: _selectedYear == 'All' ? 'Year' : 'Year: $_selectedYear',
            isSelected: _selectedYear != 'All' || isYearOpen,
            onTap: () => _openFilterStrip(FilterDimension.year, _yearPillFocusNode),
          ),
          const SizedBox(width: 12),
          TvPillChip(
            focusNode: _ratingPillFocusNode,
            label: _selectedRating == 'All' ? 'Rating' : 'Rating: $_selectedRating',
            isSelected: _selectedRating != 'All' || isRatingOpen,
            onTap: () => _openFilterStrip(FilterDimension.rating, _ratingPillFocusNode),
          ),
          const SizedBox(width: 12),
          TvPillChip(
            focusNode: _sortPillFocusNode,
            label: _selectedSort == 'Popular' ? 'Sort' : 'Sort: $_selectedSort',
            isSelected: _selectedSort != 'Popular' || isSortOpen,
            onTap: () => _openFilterStrip(FilterDimension.sort, _sortPillFocusNode),
          ),
        ],
      ),
    );
  }

  Widget _buildGridArea() {
    if (_isLoading && _items.isEmpty) {
      return _buildSkeletonGrid();
    }

    if (_errorMessage != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: TVTheme.primary),
            const SizedBox(height: 16),
            Text(
              'Failed to load catalog: $_errorMessage',
              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TvFocusButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _fetchLane(page: 1, reset: true),
            ),
          ],
        ),
      );
    }

    if (!_isLoading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_filter_outlined, size: 48, color: TVTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'No movies or shows found matching these filters.',
              style: TextStyle(color: TVTheme.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TvFocusButton(
              label: 'Reset Filters',
              icon: Icons.filter_alt_off_rounded,
              isPrimary: false,
              onPressed: _clearFilters,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            key: PageStorageKey('lane_grid_${widget.dashboardId}_${widget.laneId}'),
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 150 / 225,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final movie = _items[index];
              return FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: 162,
                  height: 241,
                  child: TvFocusCard(
                    key: ValueKey('movie_${movie.imdbId}_$index'),
                    posterUrl: movie.posterUrl,
                    title: movie.title,
                    rating: movie.ratingScore > 0 ? movie.ratingScore : null,
                    year: movie.year.isNotEmpty ? movie.year : null,
                    isTv: movie.isTv,
                    width: 150,
                    height: 225,
                    showTitleBelow: false,
                    onTap: () {
                      if (widget.onMovieSelected != null) {
                        widget.onMovieSelected!(movie);
                      }
                    },
                    onFocusChanged: (focused) {
                      if (focused) {
                        _onCardFocused(index);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        if (_isFetchingMore)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.primary),
                ),
                SizedBox(width: 10),
                Text(
                  'Loading more titles...',
                  style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          )
        else if (!_hasMore && _items.isNotEmpty)
          _buildEndOfCatalogBanner(),
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 150 / 225,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 10,
      itemBuilder: (context, index) => Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: FittedBox(
          fit: BoxFit.contain,
          child: Container(
            width: 150,
            height: 225,
            decoration: BoxDecoration(
              color: TVTheme.surfaceElevated,
              borderRadius: TVTheme.borderRadiusMd,
            ),
            child: const Center(
              child: Icon(
                Icons.movie_filter_outlined,
                size: 40,
                color: TVTheme.surface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndOfCatalogBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 48, child: Divider(color: TVTheme.surfaceElevated, thickness: 1)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'End of Catalog',
              style: TextStyle(
                color: TVTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 48, child: Divider(color: TVTheme.surfaceElevated, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildFilterStrip() {
    final dimension = _activeFilterDimension!;
    final title = _getFilterStripTitle(dimension);
    final options = _getFilterStripOptions(dimension);
    final selectedOption = _getCurrentFilterValue(dimension);

    return Container(
      decoration: BoxDecoration(
        color: TVTheme.surface,
        borderRadius: TVTheme.borderRadiusMd,
        border: Border.all(
          color: TVTheme.surfaceElevated,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: TVTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '‹ Back',
                style: TextStyle(
                  fontSize: 12,
                  color: TVTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: TVTheme.surfaceElevated, height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final option = options[index];
                final isSelected = option == selectedOption;
                return _FilterOptionTile(
                  key: ValueKey('filter_option_${dimension.name}_$option'),
                  label: option,
                  isSelected: isSelected,
                  autofocus: isSelected,
                  onSelect: () => _applyFilterOption(dimension, option),
                  onDismiss: _closeFilterStrip,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterOptionTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onSelect;
  final VoidCallback onDismiss;

  const _FilterOptionTile({
    super.key,
    required this.label,
    required this.isSelected,
    required this.autofocus,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_FilterOptionTile> createState() => _FilterOptionTileState();
}

class _FilterOptionTileState extends State<_FilterOptionTile> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Border border;

    if (_isFocused) {
      bgColor = widget.isSelected
          ? TVTheme.primary.withValues(alpha: 0.25)
          : TVTheme.surfaceElevated;
      border = Border.all(
        color: Colors.white,
        width: TVTheme.focusBorderWidth,
      );
    } else if (widget.isSelected) {
      bgColor = TVTheme.surfaceElevated;
      border = Border.all(
        color: TVTheme.primary.withValues(alpha: 0.7),
        width: 1.5,
      );
    } else {
      bgColor = Colors.transparent;
      border = Border.all(
        color: Colors.transparent,
        width: TVTheme.focusBorderWidth,
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: TVTheme.focusDuration,
            curve: Curves.easeInOut,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (TvShortcuts.isActivateKey(event.logicalKey)) {
            widget.onSelect();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            widget.onDismiss();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: TVTheme.focusDuration,
          curve: TVTheme.focusCurve,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: TVTheme.borderRadiusMd,
            border: border,
            boxShadow: _isFocused ? TVTheme.focusShadows : TVTheme.restingShadows,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: (_isFocused || widget.isSelected)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: (_isFocused || widget.isSelected)
                        ? TVTheme.textPrimary
                        : TVTheme.textSecondary,
                  ),
                ),
              ),
              if (widget.isSelected)
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: _isFocused ? Colors.white : TVTheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
