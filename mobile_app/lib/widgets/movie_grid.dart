import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'movie_card.dart';

typedef MoviePageFetcher = Future<List<Movie>> Function(
  int page, {
  dynamic genreId,
  int? year,
});

class MovieGrid extends StatefulWidget {
  final String? title;
  final List<Movie>? initialMovies;
  final MoviePageFetcher? onFetchPage;
  final bool showFilters;
  final bool endlessYearPaging;
  final Widget? header;
  final String emptyMessage;
  final EdgeInsetsGeometry padding;
  final ScrollController? scrollController;

  const MovieGrid({
    super.key,
    this.title,
    this.initialMovies,
    this.onFetchPage,
    this.showFilters = true,
    this.endlessYearPaging = false,
    this.header,
    this.emptyMessage = 'No movies found',
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.scrollController,
  });

  @override
  State<MovieGrid> createState() => _MovieGridState();
}

class _MovieGridState extends State<MovieGrid> {
  late ScrollController _scrollController;
  bool _ownsController = false;

  final List<Movie> _movies = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;

  dynamic _selectedGenreId;
  int? _selectedYear;
  int _endlessCurrentYear = DateTime.now().year;

  // Preset genres from TMDB mapping (fallback if backend filters endpoint is offline)
  List<Map<String, dynamic>> _genreOptions = [
    {'id': null, 'label': 'All Genres'},
    {'id': 28, 'label': 'Action'},
    {'id': 12, 'label': 'Adventure'},
    {'id': 16, 'label': 'Animation'},
    {'id': 35, 'label': 'Comedy'},
    {'id': 80, 'label': 'Crime'},
    {'id': 99, 'label': 'Documentary'},
    {'id': 18, 'label': 'Drama'},
    {'id': 10751, 'label': 'Family'},
    {'id': 14, 'label': 'Fantasy'},
    {'id': 36, 'label': 'History'},
    {'id': 27, 'label': 'Horror'},
    {'id': 10402, 'label': 'Music'},
    {'id': 9648, 'label': 'Mystery'},
    {'id': 10749, 'label': 'Romance'},
    {'id': 878, 'label': 'Sci-Fi'},
    {'id': 53, 'label': 'Thriller'},
    {'id': 10752, 'label': 'War'},
  ];

  late List<int?> _yearOptions;

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    _yearOptions = [
      null, // All
      for (int y = currentYear; y >= currentYear - 15; y--) y,
    ];

    _loadFiltersFromBackend();

    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownsController = true;
    }

    _scrollController.addListener(_onScroll);

    if (widget.initialMovies != null && widget.initialMovies!.isNotEmpty) {
      _movies.addAll(widget.initialMovies!);
      _hasMore = widget.onFetchPage != null;
    } else if (widget.onFetchPage != null) {
      _loadInitialPage();
    }
  }

  @override
  void didUpdateWidget(MovieGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMovies != null && widget.onFetchPage == null) {
      _filterInMemory();
    }
  }

  Future<void> _loadFiltersFromBackend() async {
    try {
      final filters = await ApiClient.getFilters();
      if (filters != null && mounted) {
        setState(() {
          if (filters.genres.isNotEmpty) {
            _genreOptions = [
              {'id': null, 'label': 'All Genres'},
              for (final g in filters.genres)
                {'id': g.id, 'label': g.label},
            ];
          }
          if (filters.years.isNotEmpty) {
            _yearOptions = [
              null,
              for (final y in filters.years)
                (y.id is int ? y.id as int : int.tryParse(y.id.toString())),
            ];
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (_ownsController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll - currentScroll <= 350) {
      _loadMore();
    }
  }

  Future<void> _loadInitialPage() async {
    if (widget.onFetchPage == null) return;
    setState(() {
      _isLoading = true;
      _movies.clear();
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final year = widget.endlessYearPaging && _selectedYear == null
          ? _endlessCurrentYear
          : _selectedYear;

      final results = await widget.onFetchPage!(
        _currentPage,
        genreId: _selectedGenreId,
        year: year,
      );

      if (mounted) {
        setState(() {
          _movies.addAll(results);
          _hasMore = results.isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || widget.onFetchPage == null) return;

    setState(() => _isLoadingMore = true);

    try {
      int targetPage = _currentPage + 1;
      int? targetYear = widget.endlessYearPaging && _selectedYear == null
          ? _endlessCurrentYear
          : _selectedYear;

      var results = await widget.onFetchPage!(
        targetPage,
        genreId: _selectedGenreId,
        year: targetYear,
      );

      // Endless year rollover check
      if (results.isEmpty && widget.endlessYearPaging && _selectedYear == null && _endlessCurrentYear > 1990) {
        _endlessCurrentYear--;
        targetPage = 1;
        results = await widget.onFetchPage!(
          targetPage,
          genreId: _selectedGenreId,
          year: _endlessCurrentYear,
        );
      }

      if (mounted) {
        setState(() {
          _currentPage = targetPage;
          _movies.addAll(results);
          _hasMore = results.isNotEmpty;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onGenreSelected(dynamic genreId) {
    if (_selectedGenreId == genreId) return;
    setState(() => _selectedGenreId = genreId);

    if (widget.onFetchPage != null) {
      _loadInitialPage();
    } else {
      _filterInMemory();
    }
  }

  void _onYearSelected(int? year) {
    if (_selectedYear == year) return;
    setState(() => _selectedYear = year);

    if (widget.onFetchPage != null) {
      _loadInitialPage();
    } else {
      _filterInMemory();
    }
  }

  void _filterInMemory() {
    if (widget.initialMovies == null) return;
    setState(() {
      _movies.clear();
      _movies.addAll(widget.initialMovies!.where((movie) {
        final matchesGenre = _selectedGenreId == null ||
            movie.genreIds.contains(_selectedGenreId);

        final matchesYear = _selectedYear == null ||
            movie.releaseDate.startsWith(_selectedYear.toString());

        return matchesGenre && matchesYear;
      }));
    });
  }

  Widget _buildFilterChips() {
    if (!widget.showFilters) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genre Chips Row
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              itemCount: _genreOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = _genreOptions[index];
                final isSelected = _selectedGenreId == option['id'];

                return ChoiceChip(
                  label: Text(
                    option['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : MobileTheme.textSecondary,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  side: BorderSide(
                    color: isSelected ? MobileTheme.accent : Colors.white12,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _onGenreSelected(option['id']),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Year Chips Row
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const BouncingScrollPhysics(),
              itemCount: _yearOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final year = _yearOptions[index];
                final isSelected = _selectedYear == year;

                return ChoiceChip(
                  label: Text(
                    year == null ? 'All Years' : year.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : MobileTheme.textSecondary,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  side: BorderSide(
                    color: isSelected ? MobileTheme.accent : Colors.white12,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _onYearSelected(year),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        if (widget.header != null)
          SliverToBoxAdapter(child: widget.header!),

        if (widget.title != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                widget.title!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: MobileTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),

        if (widget.showFilters)
          SliverToBoxAdapter(child: _buildFilterChips()),

        if (_isLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: MobileTheme.accent),
            ),
          )
        else if (_movies.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.movie_outlined, size: 48, color: MobileTheme.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    widget.emptyMessage,
                    style: const TextStyle(fontSize: 14, color: MobileTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: widget.padding,
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2 / 3.7,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => MovieCard(
                  movie: _movies[index],
                  width: double.infinity,
                  height: 160,
                ),
                childCount: _movies.length,
              ),
            ),
          ),

        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                ),
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class SliverMovieGrid extends StatelessWidget {
  final List<Movie> movies;
  final EdgeInsetsGeometry padding;

  const SliverMovieGrid({
    super.key,
    required this.movies,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2 / 3.7,
          crossAxisSpacing: 10,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => MovieCard(
            movie: movies[index],
            width: double.infinity,
            height: 160,
          ),
          childCount: movies.length,
        ),
      ),
    );
  }
}
