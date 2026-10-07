import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _history = [];
  List<Movie> _directMovies = [];
  List<TraktList> _traktLists = [];
  TraktList? _selectedList; // null = direct search/discover
  List<Movie> _displayMovies = [];

  int _page = 1;
  int _listPage = 1;
  bool _isLoading = false;
  bool _isLoadingListMovies = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _directHasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoading && !_isLoadingListMovies && !_isLoadingMore && _hasMore) {
        _fetchNextPage();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final history = await SearchHistory.getHistory();
    if (mounted) setState(() => _history = history);

    // Initial search/discover results
    final results = await ApiClient.searchMovies(page: 1);
    final traktLists = await ApiClient.searchLists(page: 1, limit: 20);

    if (mounted) {
      setState(() {
        _directMovies = results;
        _displayMovies = results;
        _traktLists = traktLists;
        _isLoading = false;
        _hasMore = results.length >= 20;
        _directHasMore = results.length >= 20;
      });
    }
  }

  Future<void> _executeSearch(String query) async {
    setState(() {
      _isLoading = true;
      _selectedList = null;
      _page = 1;
      _hasMore = true;
    });

    if (query.isNotEmpty) {
      await SearchHistory.addQuery(query);
      final history = await SearchHistory.getHistory();
      if (mounted) setState(() => _history = history);
    }

    final movies = await ApiClient.searchMovies(
      query: query.isNotEmpty ? query : null,
      page: 1,
    );

    final lists = await ApiClient.searchLists(
      query: query.isNotEmpty ? query : null,
      page: 1,
      limit: 20,
    );

    if (mounted) {
      setState(() {
        _directMovies = movies;
        _displayMovies = movies;
        _traktLists = lists;
        _isLoading = false;
        _hasMore = movies.length >= 20;
        _directHasMore = movies.length >= 20;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    if (_selectedList != null) {
      final nextListPage = _listPage + 1;
      final nextMovies = await ApiClient.getListItems(
        listId: _selectedList!.id,
        page: nextListPage,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          _listPage = nextListPage;
          _isLoadingMore = false;
          if (nextMovies.isEmpty) {
            _hasMore = false;
          } else {
            final existingKeys = _displayMovies.map((m) => m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase()).toSet();
            final uniqueNext = nextMovies.where((m) {
              final key = m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase();
              return !existingKeys.contains(key);
            }).toList();
            if (uniqueNext.isEmpty) {
              _hasMore = false;
            } else {
              _displayMovies.addAll(uniqueNext);
            }
          }
        });
      }
    } else {
      final nextPage = _page + 1;
      final query = _searchController.text.trim();

      final nextMovies = await ApiClient.searchMovies(
        query: query.isNotEmpty ? query : null,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          _page = nextPage;
          _isLoadingMore = false;
          if (nextMovies.isEmpty) {
            _hasMore = false;
            _directHasMore = false;
          } else {
            final existingKeys = _directMovies.map((m) => m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase()).toSet();
            final uniqueNext = nextMovies.where((m) {
              final key = m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase();
              return !existingKeys.contains(key);
            }).toList();
            if (uniqueNext.isEmpty) {
              _hasMore = false;
              _directHasMore = false;
            } else {
              _directMovies.addAll(uniqueNext);
              _displayMovies.addAll(uniqueNext);
            }
          }
        });
      }
    }
  }

  Future<void> _selectTraktList(TraktList list) async {
    if (_selectedList?.slug == list.slug) {
      // Toggle back to direct search
      setState(() {
        _selectedList = null;
        _displayMovies = _directMovies;
        _hasMore = _directHasMore;
      });
      return;
    }

    setState(() {
      _selectedList = list;
      _listPage = 1;
      _hasMore = true;
      _isLoadingListMovies = true;
    });

    final listMovies = await ApiClient.getListItems(listId: list.id, page: 1, limit: 20);

    if (mounted) {
      setState(() {
        _displayMovies = listMovies;
        _isLoadingListMovies = false;
        _hasMore = listMovies.isNotEmpty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (val) => setState(() {}),
            onSubmitted: (val) => _executeSearch(val.trim()),
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Search movies, series, anime...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Colors.white60, size: 18),
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        _executeSearch('');
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, color: MobileTheme.accent, size: 20),
                    tooltip: 'Search',
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      _executeSearch(_searchController.text.trim());
                    },
                  ),
                ],
              ),
              isDense: true,
              filled: true,
              fillColor: MobileTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search History Chips
          if (_history.isNotEmpty && _searchController.text.isEmpty)
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                scrollDirection: Axis.horizontal,
                itemCount: _history.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Center(
                      child: Text('Recent:', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    );
                  }
                  final item = _history[index - 1];
                  return ActionChip(
                    label: Text(item, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    backgroundColor: MobileTheme.surfaceElevated,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide.none,
                    onPressed: () {
                      _searchController.text = item;
                      setState(() {});
                      _executeSearch(item);
                    },
                  );
                },
              ),
            ),

          // Trakt Curated Lists Pill Row
          if (_traktLists.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: _traktLists.length + 1,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isAllSelected = _selectedList == null;
                    return FilterChip(
                      selected: isAllSelected,
                      label: const Text('All Direct Results', style: TextStyle(fontSize: 12)),
                      selectedColor: MobileTheme.accent,
                      checkmarkColor: Colors.white,
                      backgroundColor: MobileTheme.surfaceElevated,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide.none,
                      onSelected: (_) {
                        setState(() {
                          _selectedList = null;
                          _displayMovies = _directMovies;
                        });
                      },
                    );
                  }

                  final list = _traktLists[index - 1];
                  final isSelected = _selectedList?.slug == list.slug;

                  return FilterChip(
                    selected: isSelected,
                    label: Text('${list.name} (${list.itemCount})', style: const TextStyle(fontSize: 12)),
                    selectedColor: MobileTheme.accent,
                    checkmarkColor: Colors.white,
                    backgroundColor: MobileTheme.surfaceElevated,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    side: BorderSide.none,
                    onSelected: (_) => _selectTraktList(list),
                  );
                },
              ),
            ),

          // Results Grid with Pull-to-Refresh
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _executeSearch(_searchController.text.trim()),
              color: MobileTheme.accent,
              backgroundColor: MobileTheme.surfaceElevated,
              child: _isLoading || _isLoadingListMovies
                  ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
                  : (_displayMovies.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                            _buildEmptyState(),
                          ],
                        )
                      : _buildGrid()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (ApiClient.isServerlessMode && !ApiClient.hasTmdbKey) {
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
                child: const Icon(Icons.vpn_key_rounded, color: MobileTheme.accent, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'TMDb Key Required',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Direct global search and recommendations require a free TMDb API key in Serverless Mode.',
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
                onPressed: () => _executeSearch(_searchController.text.trim()),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white30, size: 54),
          const SizedBox(height: 12),
          const Text('No titles found', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Try searching with different keywords or check spelling.', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
            label: const Text('Reload Results'),
            onPressed: () => _executeSearch(_searchController.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3.7,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: _displayMovies.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _displayMovies.length) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
            ),
          );
        }
        final movie = _displayMovies[index];
        return MovieCard(
          movie: movie,
          width: double.infinity,
          height: 160,
        );
      },
    );
  }
}
