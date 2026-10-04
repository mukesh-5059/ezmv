import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api_client.dart';
import '../core/search_history.dart';
import '../models/movie.model.dart';
import '../models/trakt_list.model.dart';
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
  final ScrollController _listsScrollController = ScrollController();
  late final FocusNode _textFieldFocusNode = FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack) {
          _submitSearchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _submitSearchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (_searchController.text.isNotEmpty && _clearSearchFocusNode.canRequestFocus) {
            _clearSearchFocusNode.requestFocus();
          } else {
            _submitSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
  );
  final FocusNode _clearSearchFocusNode = FocusNode();
  final FocusNode _submitSearchFocusNode = FocusNode();

  List<String> _history = [];
  List<Movie> _directMovies = [];
  List<TraktList> _traktLists = [];
  TraktList? _selectedList; // null means viewing direct search movies
  List<Movie> _displayMovies = [];

  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingListMovies = false;
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
    _listsScrollController.dispose();
    _textFieldFocusNode.dispose();
    _clearSearchFocusNode.dispose();
    _submitSearchFocusNode.dispose();
    super.dispose();
  }

  void _onGridScroll() {
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingListMovies && !_isLoadingMore && _hasMore) {
        _fetchNextPage();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final historyList = await SearchHistory.getHistory();
    if (mounted) {
      setState(() => _history = historyList);
    }
    await _executeSearch(resetPage: true);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _submitSearchFocusNode.canRequestFocus) {
          _submitSearchFocusNode.requestFocus();
        }
      });
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
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _submitSearchFocusNode.canRequestFocus) {
          _submitSearchFocusNode.requestFocus();
        }
      });
    }
  }

  Future<void> _executeSearch({bool resetPage = false}) async {
    if (resetPage) {
      _page = 1;
      _hasMore = true;
      _selectedList = null;
    }

    setState(() => _isLoading = true);

    final query = _searchController.text.trim();
    final results = await Future.wait([
      ApiClient.searchMovies(
        query: query.isNotEmpty ? query : null,
        page: 1,
      ),
      ApiClient.searchLists(
        query: query.isNotEmpty ? query : null,
        page: 1,
        limit: 20,
      ),
    ]);

    final movies = results[0] as List<Movie>;
    final lists = results[1] as List<TraktList>;

    if (mounted) {
      setState(() {
        _directMovies = movies;
        _displayMovies = movies;
        _traktLists = lists;
        _isLoading = false;
        _hasMore = movies.length >= 20;
      });
    }
  }

  Future<void> _selectList(TraktList? list) async {
    if (list == null) {
      // Switch back to direct search results
      setState(() {
        _selectedList = null;
        _displayMovies = _directMovies;
        _hasMore = _directMovies.length >= 20;
        _page = 1;
      });
      return;
    }

    setState(() {
      _selectedList = list;
      _isLoadingListMovies = true;
      _displayMovies = [];
      _page = 1;
      _hasMore = true;
    });

    final listMovies = await ApiClient.getListItems(listId: list.id, page: 1, limit: 20);

    if (mounted) {
      setState(() {
        _displayMovies = listMovies;
        _isLoadingListMovies = false;
        _hasMore = listMovies.isNotEmpty && (list.itemCount == 0 || listMovies.length < list.itemCount);
      });
    }
  }

  Future<void> _fetchNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _page + 1;
    List<Movie> newItems = [];

    if (_selectedList != null) {
      newItems = await ApiClient.getListItems(
        listId: _selectedList!.id,
        page: nextPage,
        limit: 20,
      );
    } else {
      final query = _searchController.text.trim();
      newItems = await ApiClient.searchMovies(
        query: query.isNotEmpty ? query : null,
        page: nextPage,
      );
    }

    if (mounted) {
      setState(() {
        if (newItems.isNotEmpty) {
          final existingIds = _displayMovies.map((m) => m.tmdbId).toSet();
          final uniqueNew = newItems.where((m) => !existingIds.contains(m.tmdbId)).toList();
          _displayMovies.addAll(uniqueNew);
          _page = nextPage;
          _hasMore = _selectedList != null
              ? (_displayMovies.length < _selectedList!.itemCount && newItems.isNotEmpty)
              : newItems.length >= 20;
        } else {
          _hasMore = false;
        }
        _isLoadingMore = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _executeSearch(resetPage: true);
    _submitSearchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TVTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopSearchBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Lists / Collections
                  SizedBox(
                    width: 360,
                    child: _buildListsPane(),
                  ),
                  Container(
                    width: 1,
                    color: TVTheme.surfaceElevated.withValues(alpha: 0.6),
                  ),
                  // Right Pane: Movies Grid
                  Expanded(
                    child: _buildMoviesPane(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: TVTheme.surface.withValues(alpha: 0.7),
        border: Border(
          bottom: BorderSide(
            color: TVTheme.surfaceElevated.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: TVTheme.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: TVTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _textFieldFocusNode.hasFocus
                          ? TVTheme.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Icon(Icons.search, color: TVTheme.textSecondary, size: 22),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _textFieldFocusNode,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                            color: TVTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search movies, franchises, or curated lists (e.g. Marvel, Batman, Nolan)...',
                            hintStyle: TextStyle(
                              color: TVTheme.textSecondary,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: _onQuerySubmitted,
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          focusNode: _clearSearchFocusNode,
                          icon: const Icon(Icons.close, color: TVTheme.textSecondary, size: 20),
                          onPressed: _clearSearch,
                        ),
                      FocusableActionDetector(
                        focusNode: _submitSearchFocusNode,
                        autofocus: true,
                        onShowFocusHighlight: (v) => setState(() {}),
                        actions: {
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) => _onQuerySubmitted(_searchController.text),
                          ),
                        },
                        child: InkWell(
                          onTap: () => _onQuerySubmitted(_searchController.text),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _submitSearchFocusNode.hasFocus
                                  ? TVTheme.accent
                                  : TVTheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: _submitSearchFocusNode.hasFocus
                                      ? Colors.black
                                      : TVTheme.textPrimary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Search',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _submitSearchFocusNode.hasFocus
                                        ? Colors.black
                                        : TVTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Recent:',
                    style: TextStyle(
                      color: TVTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ..._history.take(6).map((term) => _buildHistoryChip(term)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryChip(String term) {
    return Builder(
      builder: (chipContext) {
        return Container(
          margin: const EdgeInsets.only(right: 8),
          child: FocusableActionDetector(
            onFocusChange: (focused) {
              if (focused) {
                Scrollable.ensureVisible(
                  chipContext,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 200),
                );
              }
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _searchController.text = term;
                  _onQuerySubmitted(term);
                  return null;
                },
              ),
            },
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return InkWell(
                  onTap: () {
                    _searchController.text = term;
                    _onQuerySubmitted(term);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFocused ? TVTheme.accent : TVTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFocused ? TVTheme.accent : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 13,
                          color: isFocused ? Colors.black : TVTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          term,
                          style: TextStyle(
                            fontSize: 12,
                            color: isFocused ? Colors.black : TVTheme.textPrimary,
                            fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildListsPane() {
    return Container(
      color: TVTheme.surface.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                const Icon(Icons.playlist_play, color: TVTheme.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  _searchController.text.trim().isNotEmpty ? 'MATCHING LISTS' : 'POPULAR LISTS',
                  style: const TextStyle(
                    color: TVTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _listsScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              children: [
                // Top Default Tile: Direct Movie Results
                _buildDirectMoviesTile(),
                const SizedBox(height: 8),
                const Divider(color: TVTheme.surfaceElevated, height: 1),
                const SizedBox(height: 8),
                // Trakt Lists
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                    ),
                  )
                else if (_traktLists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No matching lists found.',
                      style: TextStyle(
                        color: TVTheme.textSecondary.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                  )
                else
                  ..._traktLists.map((list) => _buildTraktListTile(list)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectMoviesTile() {
    final isSelected = _selectedList == null;
    return Builder(
      builder: (tileContext) {
        return FocusableActionDetector(
          onFocusChange: (focused) {
            if (focused) {
              Scrollable.ensureVisible(
                tileContext,
                alignment: 0.5,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _selectList(null);
                return null;
              },
            ),
          },
          child: Builder(
            builder: (context) {
              final isFocused = Focus.of(context).hasFocus;
              return InkWell(
                onTap: () => _selectList(null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isFocused
                        ? TVTheme.surfaceElevated
                        : (isSelected
                            ? const Color(0xFF26181B)
                            : TVTheme.surface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused
                          ? Colors.white
                          : (isSelected ? TVTheme.accent : Colors.transparent),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected ? TVTheme.accent : TVTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.movie,
                          color: isSelected ? Colors.white : TVTheme.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Direct Movie Results',
                              style: TextStyle(
                                color: TVTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_directMovies.length} movies found',
                              style: const TextStyle(
                                color: TVTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle, color: TVTheme.accent, size: 18),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTraktListTile(TraktList list) {
    final isSelected = _selectedList?.id == list.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Builder(
        builder: (tileContext) {
          return FocusableActionDetector(
            onFocusChange: (focused) {
              if (focused) {
                Scrollable.ensureVisible(
                  tileContext,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                );
              }
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _selectList(list);
                  return null;
                },
              ),
            },
            child: Builder(
              builder: (context) {
                final isFocused = Focus.of(context).hasFocus;
                return InkWell(
                  onTap: () => _selectList(list),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isFocused
                          ? TVTheme.surfaceElevated
                          : (isSelected
                              ? const Color(0xFF26181B)
                              : TVTheme.surface),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFocused
                            ? Colors.white
                            : (isSelected ? TVTheme.accent : Colors.transparent),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                list.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isFocused ? Colors.white : (isSelected ? TVTheme.accent : TVTheme.textPrimary),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: TVTheme.accent, size: 16),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (list.userName.isNotEmpty) ...[
                              Text(
                                'by ${list.userName}',
                                style: const TextStyle(
                                  color: TVTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: TVTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${list.itemCount} items',
                                style: const TextStyle(
                                  color: TVTheme.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (list.likes > 0) ...[
                              const SizedBox(width: 6),
                              Row(
                                children: [
                                  const Icon(Icons.thumb_up, color: TVTheme.accent, size: 10),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${list.likes}',
                                    style: const TextStyle(
                                      color: TVTheme.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoviesPane() {
    final query = _searchController.text.trim();
    final headerTitle = _selectedList != null
        ? 'List: ${_selectedList!.name} (${_selectedList!.itemCount > 0 ? '${_displayMovies.length}/${_selectedList!.itemCount}' : '${_displayMovies.length}'} items)'
        : (query.isNotEmpty
            ? 'Direct Search: "$query" (${_displayMovies.length} movies)'
            : 'Popular / Trending Movies (${_displayMovies.length} movies)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  headerTitle,
                  style: const TextStyle(
                    color: TVTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_isLoading || _isLoadingListMovies)
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TVTheme.accent,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: TVTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading || _isLoadingListMovies
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: TVTheme.accent),
                      SizedBox(height: 16),
                      Text(
                        'Awaiting movie results...',
                        style: TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : _displayMovies.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.movie_filter_outlined,
                            size: 64,
                            color: TVTheme.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No Movies Found',
                            style: TextStyle(
                              color: TVTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Try selecting a list on the left or entering a different query.',
                            style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      controller: _gridScrollController,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.64,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final movie = _displayMovies[index];
                                return MovieCard(
                                  movie: movie,
                                  onFocusChanged: (focused) {
                                    if (focused && index >= _displayMovies.length - 8 && !_isLoadingMore && _hasMore) {
                                      _fetchNextPage();
                                    }
                                  },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => DetailsScreen(movie: movie),
                                      ),
                                    );
                                  },
                                );
                              },
                              childCount: _displayMovies.length,
                            ),
                          ),
                        ),
                        if (_isLoadingMore)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: TVTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: TVTheme.accent,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Loading more movies...',
                                        style: TextStyle(
                                          color: TVTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        else if (!_hasMore && _displayMovies.isNotEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Divider(color: TVTheme.surfaceElevated),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'End of results',
                                      style: TextStyle(
                                        color: TVTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Divider(color: TVTheme.surfaceElevated),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}
