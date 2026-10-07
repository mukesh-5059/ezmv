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
  TraktList? _selectedList; // null = list index, non-null = list details
  List<Movie> _displayMovies = []; // movies inside the selected TraktList

  int _selectedTabIndex = 0; // 0: Curated Lists, 1: Movies
  bool _isDescExpanded = false;
  bool _showBackToTop = false;

  int _directPage = 1;
  int _listPage = 1;
  bool _isLoading = false;
  bool _isLoadingListMovies = false;
  bool _isLoadingMore = false;
  bool _directHasMore = true;
  bool _hasMore = true;

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
    if (_scrollController.hasClients) {
      final showBtn = _scrollController.offset > 250;
      if (showBtn != _showBackToTop) {
        setState(() => _showBackToTop = showBtn);
      }
    }

    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingListMovies && !_isLoadingMore) {
        if (_selectedTabIndex == 0 && _selectedList != null && _hasMore) {
          _fetchNextPage();
        } else if (_selectedTabIndex == 1 && _directHasMore) {
          _fetchNextPage();
        }
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
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
        _traktLists = traktLists;
        _isLoading = false;
        _directHasMore = results.length >= 20;
      });
    }
  }

  Future<void> _executeSearch(String query) async {
    setState(() {
      _isLoading = true;
      _selectedList = null;
      _displayMovies = [];
      _isDescExpanded = false;
      _directPage = 1;
      _listPage = 1;
      _directHasMore = true;
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
        _traktLists = lists;
        _isLoading = false;
        _directHasMore = movies.length >= 20;
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore) return;

    if (_selectedTabIndex == 0 && _selectedList != null) {
      if (!_hasMore) return;
      setState(() => _isLoadingMore = true);
      final nextListPage = _listPage + 1;
      final nextMovies = await ApiClient.getListItems(
        listId: _selectedList!.id,
        page: nextListPage,
        limit: 50,
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
            _displayMovies.addAll(uniqueNext);
            if (nextMovies.length < 50) {
              _hasMore = false;
            }
          }
        });
      }
    } else if (_selectedTabIndex == 1) {
      if (!_directHasMore) return;
      setState(() => _isLoadingMore = true);
      final nextPage = _directPage + 1;
      final query = _searchController.text.trim();

      final nextMovies = await ApiClient.searchMovies(
        query: query.isNotEmpty ? query : null,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          _directPage = nextPage;
          _isLoadingMore = false;
          if (nextMovies.isEmpty) {
            _directHasMore = false;
          } else {
            final existingKeys = _directMovies.map((m) => m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase()).toSet();
            final uniqueNext = nextMovies.where((m) {
              final key = m.tmdbId > 0 ? '${m.mediaType}_${m.tmdbId}' : m.title.toLowerCase();
              return !existingKeys.contains(key);
            }).toList();
            _directMovies.addAll(uniqueNext);
            if (nextMovies.length < 20) {
              _directHasMore = false;
            }
          }
        });
      }
    }
  }

  Future<void> _selectTraktList(TraktList list) async {
    setState(() {
      _selectedList = list;
      _displayMovies = [];
      _isDescExpanded = false;
      _listPage = 1;
      _hasMore = true;
      _isLoadingListMovies = true;
    });

    final listMovies = await ApiClient.getListItems(listId: list.id, page: 1, limit: 50);

    if (mounted) {
      setState(() {
        _displayMovies = listMovies;
        _isLoadingListMovies = false;
        _hasMore = listMovies.length >= 50;
      });
    }
  }

  void _clearSelectedList() {
    setState(() {
      _selectedList = null;
      _displayMovies = [];
      _isDescExpanded = false;
      _hasMore = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: AnimatedScale(
        scale: _showBackToTop ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _showBackToTop ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton.small(
            backgroundColor: MobileTheme.accent,
            foregroundColor: Colors.white,
            elevation: 4,
            tooltip: 'Back to Top',
            onPressed: _scrollToTop,
            child: const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ),
      ),
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

          // Top Segmented View: [ Curated Lists (N) ] | [ Movies (N) ]
          _buildSegmentedControl(),

          // Active Tab Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_selectedTabIndex == 0 && _selectedList != null) {
                  await _selectTraktList(_selectedList!);
                } else {
                  await _executeSearch(_searchController.text.trim());
                }
              },
              color: MobileTheme.accent,
              backgroundColor: MobileTheme.surfaceElevated,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
                  : (_selectedTabIndex == 0 ? _buildListsTab() : _buildMoviesTab()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: MobileTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10, width: 0.8),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSegmentButton(
                index: 0,
                label: 'Curated Lists',
                count: _traktLists.length,
                icon: Icons.collections_bookmark_rounded,
              ),
            ),
            Expanded(
              child: _buildSegmentButton(
                index: 1,
                label: 'Movies',
                count: _directMovies.length,
                icon: Icons.movie_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required int index,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        if (_selectedTabIndex != index) {
          setState(() => _selectedTabIndex = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? MobileTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(2.5),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black26 : Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- CURATED LISTS TAB ---
  Widget _buildListsTab() {
    // When inside a selected list
    if (_selectedList != null) {
      if (_isLoadingListMovies) {
        return const Center(child: CircularProgressIndicator(color: MobileTheme.accent));
      }

      return CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          // List Header Banner
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MobileTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MobileTheme.accent.withValues(alpha: 0.3), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: _clearSelectedList,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white70),
                              SizedBox(width: 4),
                              Text('All Lists', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MobileTheme.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_selectedList!.itemCount} items',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _selectedList!.name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_selectedList!.userName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Curated by @${_selectedList!.userName}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                  if (_selectedList!.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => setState(() => _isDescExpanded = !_isDescExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedList!.description.trim(),
                            maxLines: _isDescExpanded ? null : 2,
                            overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                          ),
                          if (_selectedList!.description.trim().length > 80 || _selectedList!.description.contains('\n'))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _isDescExpanded ? 'Show less ▲' : 'Show more ▼',
                                style: const TextStyle(color: MobileTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_displayMovies.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(
                title: 'No Movies in List',
                subtitle: 'This curated list does not have any items available.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2 / 3.7,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => MovieCard(
                    movie: _displayMovies[index],
                    width: double.infinity,
                    height: 160,
                  ),
                  childCount: _displayMovies.length,
                ),
              ),
            ),

            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                    ),
                  ),
                ),
              ),

            if (!_hasMore && _displayMovies.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildEndOfPageMarker(
                  count: _displayMovies.length,
                  label: _selectedList!.name,
                ),
              ),
          ],
        ],
      );
    }

    // List Index View (Cards)
    if (_traktLists.isEmpty) {
      if (ApiClient.isServerlessMode && !ApiClient.hasTraktKey) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            _buildTraktKeyRequiredState(),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          _buildEmptyState(
            title: 'No Curated Lists Found',
            subtitle: 'Try searching with different keywords to explore community lists.',
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildListCard(_traktLists[index]),
              childCount: _traktLists.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _buildEndOfPageMarker(
            count: _traktLists.length,
            label: 'Curated Lists',
          ),
        ),
      ],
    );
  }

  Widget _buildListCard(TraktList list) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MobileTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectTraktList(list),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MobileTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.video_library_rounded,
                        color: MobileTheme.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            list.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (list.userName.isNotEmpty)
                                Text(
                                  'by @${list.userName}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              if (list.userName.isNotEmpty && list.likes > 0)
                                const Text(' • ', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              if (list.likes > 0)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 11),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${list.likes}',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${list.itemCount} items',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (list.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    list.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- MOVIES TAB ---
  Widget _buildMoviesTab() {
    if (_directMovies.isEmpty) {
      if (ApiClient.isServerlessMode && !ApiClient.hasTmdbKey) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            _buildTmdbKeyRequiredState(),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          _buildEmptyState(
            title: 'No titles found',
            subtitle: 'Try searching with different keywords or check spelling.',
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2 / 3.7,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => MovieCard(
                movie: _directMovies[index],
                width: double.infinity,
                height: 160,
              ),
              childCount: _directMovies.length,
            ),
          ),
        ),

        if (_isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MobileTheme.accent),
                ),
              ),
            ),
          ),

        if (!_directHasMore && _directMovies.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildEndOfPageMarker(
              count: _directMovies.length,
              label: 'Movies & Series',
            ),
          ),
      ],
    );
  }

  // --- END OF PAGE MARKER ---
  Widget _buildEndOfPageMarker({
    required int count,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider(color: Colors.white12, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'End of $label ($count loaded)',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(child: Divider(color: Colors.white12, height: 1)),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: MobileTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              backgroundColor: MobileTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.white10),
              ),
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 16),
            label: const Text('Back to Top', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: _scrollToTop,
          ),
        ],
      ),
    );
  }

  // --- EMPTY STATES ---
  Widget _buildTmdbKeyRequiredState() {
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

  Widget _buildTraktKeyRequiredState() {
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
              'Curated lists and community collections require a Trakt Client ID in Self-Serving mode.',
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

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, color: Colors.white30, size: 54),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
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
      ),
    );
  }
}
