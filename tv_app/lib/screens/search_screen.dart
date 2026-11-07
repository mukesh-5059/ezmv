import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../widgets/tv_focus_button.dart';
import '../widgets/tv_focus_card.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  late final FocusNode _textFieldFocusNode;
  final FocusNode _submitSearchFocusNode = FocusNode();
  final FocusNode _clearSearchFocusNode = FocusNode();

  List<String> _history = [];
  List<MovieSummary> _movies = [];
  List<TraktListSummary> _traktLists = [];
  TraktListSummary? _selectedList;

  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  static const String _historyKey = 'tv_search_history';

  @override
  void initState() {
    super.initState();
    _textFieldFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _submitSearchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _loadHistory();
    _gridScrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    _textFieldFocusNode.dispose();
    _submitSearchFocusNode.dispose();
    _clearSearchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    if (mounted) setState(() => _history = list);
  }

  Future<void> _saveHistory(String query) async {
    if (query.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? [];
    list.remove(query);
    list.insert(0, query);
    if (list.length > 10) list.removeRange(10, list.length);
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  void _onScroll() {
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _fetchNextPage();
      }
    }
  }

  Future<void> _executeSearch({bool resetPage = true}) async {
    if (resetPage) {
      _page = 1;
      _hasMore = true;
      _selectedList = null;
    }

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _movies = [];
        _traktLists = [];
        _isLoading = false;
      });
      return;
    }

    _saveHistory(query);
    setState(() => _isLoading = true);

    try {
      final movieResp = await ApiClient.instance.search(query, page: 1);
      if (mounted) {
        setState(() {
          _movies = movieResp.items;
          _isLoading = false;
          _hasMore = movieResp.hasMore;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }

    try {
      final listResp = await ApiClient.instance.searchLists(query, page: 1);
      if (mounted) {
        setState(() {
          _traktLists = listResp.items;
        });
      }
    } catch (_) {
      // Ignored: list search failure or rate-limiting should not affect movie results
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _page + 1;
      final query = _searchController.text.trim();

      if (_selectedList != null) {
        final resp = await ApiClient.instance.getListItems(_selectedList!.id, page: nextPage);
        if (mounted) {
          setState(() {
            _page = nextPage;
            _movies.addAll(resp.items);
            _hasMore = resp.hasMore;
            _isLoadingMore = false;
          });
        }
      } else {
        final resp = await ApiClient.instance.search(query, page: nextPage);
        if (mounted) {
          setState(() {
            _page = nextPage;
            _movies.addAll(resp.items);
            _hasMore = resp.hasMore;
            _isLoadingMore = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _selectList(TraktListSummary? list) async {
    if (list == null) {
      _executeSearch(resetPage: true);
      return;
    }

    setState(() {
      _selectedList = list;
      _isLoading = true;
      _page = 1;
      _hasMore = true;
    });

    try {
      final resp = await ApiClient.instance.getListItems(list.id, page: 1);
      if (mounted) {
        setState(() {
          _movies = resp.items;
          _isLoading = false;
          _hasMore = resp.hasMore;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToDetails(MovieSummary movie) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailsScreen(
          imdbId: movie.imdbId,
          mediaType: movie.mediaType,
          initialMovie: movie,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TVTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TVTheme.overscanMargin,
            vertical: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Header Row
              _buildSearchHeader(),
              const SizedBox(height: 16),

              // Search History / Suggestions Row
              if (_history.isNotEmpty && _movies.isEmpty && !_isLoading) ...[
                _buildHistoryRow(),
                const SizedBox(height: 16),
              ],

              // Trakt Lists Shelf (if query returned lists)
              if (_traktLists.isNotEmpty) ...[
                _buildListsShelf(),
                const SizedBox(height: 16),
              ],

              // Results Grid
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: TVTheme.primary),
                      )
                    : _movies.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search, size: 56, color: TVTheme.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  _searchController.text.trim().isEmpty
                                      ? 'Type a title, actor, or genre above to search.'
                                      : 'No titles found matching "${_searchController.text.trim()}".',
                                  style: const TextStyle(color: TVTheme.textSecondary, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : _buildMovieGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _textFieldFocusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 18, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search movies, TV shows, lists...',
              hintStyle: const TextStyle(color: TVTheme.textMuted),
              filled: true,
              fillColor: TVTheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: TVTheme.borderRadiusMd,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: TVTheme.borderRadiusMd,
                borderSide: const BorderSide(color: Colors.white, width: 2),
              ),
            ),
            onSubmitted: (q) => _executeSearch(resetPage: true),
          ),
        ),
        const SizedBox(width: 16),
        TvFocusButton(
          focusNode: _submitSearchFocusNode,
          label: 'Search',
          isPrimary: true,
          icon: Icons.search,
          onPressed: () => _executeSearch(resetPage: true),
        ),
        const SizedBox(width: 12),
        if (_searchController.text.isNotEmpty)
          TvFocusButton(
            focusNode: _clearSearchFocusNode,
            label: 'Clear',
            isPrimary: false,
            onPressed: () {
              _searchController.clear();
              setState(() {
                _movies = [];
                _traktLists = [];
                _selectedList = null;
              });
              _textFieldFocusNode.requestFocus();
            },
          ),
      ],
    );
  }

  Widget _buildHistoryRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Searches',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _history.length,
            itemBuilder: (ctx, idx) {
              final item = _history[idx];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TvFocusButton(
                  label: item,
                  isPrimary: false,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  onPressed: () {
                    _searchController.text = item;
                    _executeSearch(resetPage: true);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListsShelf() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Matched Trakt Lists',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (_selectedList != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _selectList(null),
                child: const Text(
                  '(Show All Direct Results)',
                  style: TextStyle(color: TVTheme.primary, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _traktLists.length,
            itemBuilder: (ctx, idx) {
              final list = _traktLists[idx];
              final isSelected = _selectedList?.id == list.id;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TvFocusButton(
                  label: '${list.name} (${list.itemCount})',
                  isPrimary: isSelected,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  onPressed: () => _selectList(isSelected ? null : list),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMovieGrid() {
    return GridView.builder(
      controller: _gridScrollController,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        childAspectRatio: 0.58,
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
      ),
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return TvFocusCard(
          posterUrl: movie.posterUrl,
          title: movie.title,
          rating: movie.ratingScore > 0 ? movie.ratingScore : null,
          year: movie.year.isNotEmpty ? movie.year : null,
          isTv: movie.isTv,
          showTitleBelow: true,
          onTap: () => _navigateToDetails(movie),
        );
      },
    );
  }
}
