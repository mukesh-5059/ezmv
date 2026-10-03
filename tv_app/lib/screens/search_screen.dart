import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/search_history.dart';
import '../models/movie.model.dart';
import '../models/filter.model.dart';
import '../widgets/movie_card.dart';
import '../theme.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final FocusNode _textFieldFocusNode = FocusNode();
  final FocusNode _clearSearchFocusNode = FocusNode();
  final FocusNode _submitSearchFocusNode = FocusNode();

  FiltersData _filters = const FiltersData();
  List<String> _history = [];
  List<Movie> _movies = [];

  String _selectedLanguage = 'all';
  dynamic _selectedGenre;
  FilterOption? _selectedYear;
  String _selectedSort = 'popularity.desc';

  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _gridScrollController.addListener(_onGridScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    _sidebarScrollController.dispose();
    _textFieldFocusNode.dispose();
    _clearSearchFocusNode.dispose();
    _submitSearchFocusNode.dispose();
    super.dispose();
  }

  void _onGridScroll() {
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchNextPage();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final historyList = await SearchHistory.getHistory();
    final filtersData = await ApiClient.getFilters();

    if (mounted) {
      setState(() {
        _history = historyList;
        if (filtersData != null) {
          _filters = filtersData;
          if (_filters.years.isNotEmpty) {
            _selectedYear = _filters.years.first;
          }
        }
      });
      await _executeSearch(resetPage: true);
    }
  }

  void _onQuerySubmitted(String query) {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      SearchHistory.addQuery(trimmed).then((_) {
        SearchHistory.getHistory().then((updated) {
          if (mounted) setState(() => _history = updated);
        });
      });
    }
    _executeSearch(resetPage: true);
  }

  Future<void> _executeSearch({bool resetPage = false}) async {
    if (resetPage) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _isLoading = true;
      });
    }

    final query = _searchController.text.trim();
    List<Movie> results = [];

    try {
      results = await ApiClient.searchMovies(
        query: query.isNotEmpty ? query : null,
        language: _selectedLanguage,
        yearMin: _selectedYear?.yearMin,
        yearMax: _selectedYear?.yearMax,
        genreId: _selectedGenre,
        sortBy: _selectedSort,
        page: _page,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        if (resetPage) {
          _movies = results;
        } else {
          _movies.addAll(results);
        }
        _hasMore = results.length >= 15;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _page += 1;
    });
    await _executeSearch(resetPage: false);
  }

  void _clearSearch() {
    _searchController.clear();
    _executeSearch(resetPage: true);
    _textFieldFocusNode.requestFocus();
  }

  void _selectHistoryItem(String item) {
    _searchController.text = item;
    _onQuerySubmitted(item);
  }

  void _clearHistory() async {
    await SearchHistory.clearHistory();
    if (mounted) {
      setState(() => _history = []);
    }
  }

  Widget _buildFilterSection<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelBuilder,
    required bool Function(T) isSelected,
    required void Function(T) onSelected,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: TVTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items.map((item) {
              final selected = isSelected(item);
              return _FilterChipWidget(
                label: labelBuilder(item),
                isSelected: selected,
                onTap: () {
                  onSelected(item);
                  _executeSearch(resetPage: true);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar() {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: TVTheme.surface,
        border: Border(
          right: BorderSide(color: Colors.white10, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Text(
                'Search & Browse',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: TVTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _textFieldFocusNode.hasFocus ? TVTheme.accent : Colors.white12,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.search, color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _textFieldFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Movie title...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: _onQuerySubmitted,
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    focusNode: _clearSearchFocusNode,
                    icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                    onPressed: _clearSearch,
                  ),
                IconButton(
                  focusNode: _submitSearchFocusNode,
                  icon: const Icon(Icons.arrow_forward, color: TVTheme.accent, size: 18),
                  onPressed: () => _onQuerySubmitted(_searchController.text),
                ),
              ],
            ),
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Searches',
                  style: TextStyle(color: TVTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: _clearHistory,
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _history.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final term = _history[index];
                  return _HistoryChipWidget(
                    label: term,
                    onTap: () => _selectHistoryItem(term),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              controller: _sidebarScrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterSection<FilterOption>(
                    title: 'LANGUAGE',
                    items: _filters.languages,
                    labelBuilder: (l) => l.label,
                    isSelected: (l) => _selectedLanguage == (l.id?.toString() ?? 'all'),
                    onSelected: (l) => setState(() => _selectedLanguage = l.id?.toString() ?? 'all'),
                  ),
                  _buildFilterSection<FilterOption>(
                    title: 'GENRE',
                    items: _filters.genres,
                    labelBuilder: (g) => g.label,
                    isSelected: (g) => _selectedGenre == g.id,
                    onSelected: (g) => setState(() => _selectedGenre = g.id),
                  ),
                  _buildFilterSection<FilterOption>(
                    title: 'RELEASE YEAR / ERA',
                    items: _filters.years,
                    labelBuilder: (y) => y.label,
                    isSelected: (y) => _selectedYear?.id == y.id,
                    onSelected: (y) => setState(() => _selectedYear = y),
                  ),
                  _buildFilterSection<FilterOption>(
                    title: 'SORT ORDER',
                    items: _filters.sortOptions,
                    labelBuilder: (s) => s.label,
                    isSelected: (s) => _selectedSort == s.id,
                    onSelected: (s) => setState(() => _selectedSort = s.id?.toString() ?? 'popularity.desc'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightGrid() {
    final queryText = _searchController.text.trim();

    if (_isLoading && _movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: TVTheme.accent),
            const SizedBox(height: 16),
            Text(
              queryText.isNotEmpty ? 'Searching for "$queryText"...' : 'Loading movies...',
              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'No Movies Found',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              queryText.isNotEmpty
                  ? 'No matches found for "$queryText". Try another title or adjust your filters.'
                  : 'No movies match your selected filter combination.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                queryText.isNotEmpty
                    ? 'Search Results for "$queryText"'
                    : 'Discovered Movies (${_movies.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isLoadingMore)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.accent),
                ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _gridScrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final movie = _movies[index];
                      return MovieCard(
                        movie: movie,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailsScreen(movie: movie),
                            ),
                          );
                        },
                      );
                    },
                    childCount: _movies.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _isLoadingMore
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: TVTheme.accent),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Loading more movies...',
                                style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (!_hasMore && _movies.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(width: 48, height: 1, color: Colors.white24),
                                const SizedBox(width: 14),
                                const Icon(Icons.check_circle_outline, size: 16, color: TVTheme.textMuted),
                                const SizedBox(width: 8),
                                const Text(
                                  'End of results',
                                  style: TextStyle(
                                    color: TVTheme.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Container(width: 48, height: 1, color: Colors.white24),
                              ],
                            ),
                          )
                        : const SizedBox(height: 24)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TVTheme.background,
      body: SafeArea(
        child: Row(
          children: [
            _buildLeftSidebar(),
            Expanded(child: _buildRightGrid()),
          ],
        ),
      ),
    );
  }
}

class _FilterChipWidget extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipWidget({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FilterChipWidget> createState() => _FilterChipWidgetState();
}

class _FilterChipWidgetState extends State<_FilterChipWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isSelected
        ? TVTheme.accent
        : (_isFocused ? Colors.white24 : Colors.white10);

    final textColor = widget.isSelected ? Colors.white : (_isFocused ? Colors.white : Colors.white70);

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? Colors.white : (widget.isSelected ? TVTheme.accent : Colors.transparent),
              width: 1.2,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryChipWidget extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _HistoryChipWidget({
    required this.label,
    required this.onTap,
  });

  @override
  State<_HistoryChipWidget> createState() => _HistoryChipWidgetState();
}

class _HistoryChipWidgetState extends State<_HistoryChipWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter ||
             event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white24 : Colors.white10,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused ? Colors.white : Colors.white12,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 11, color: Colors.white54),
              const SizedBox(width: 3),
              Text(
                widget.label,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
