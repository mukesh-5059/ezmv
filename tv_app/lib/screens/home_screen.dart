import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import '../widgets/movie_lane.dart';
import '../widgets/search_dialog.dart';
import '../widgets/settings_dialog.dart';
import 'details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Movie> _history = [];

  List<Movie> _topTamil = [];
  List<Movie> _latestTamil = [];
  List<Movie> _comedyTamil = [];

  List<Movie> _topEnglish = [];
  List<Movie> _latestEnglish = [];
  List<Movie> _comedyEnglish = [];

  List<Movie> _searchResults = [];

  Movie? _focusedMovie;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isTamilSelected = true;

  String _searchQuery = '';
  int _searchPage = 1;

  int _topTamilPage = 1;
  int _latestTamilPage = 1;
  int _comedyTamilPage = 1;

  int _topEnglishPage = 1;
  int _latestEnglishPage = 1;
  int _comedyEnglishPage = 1;

  String? _activeSearchText;
  int? _activeSearchYear;
  int? _activeSearchGenreId;

  bool _isLoadingMore = false;

  final FocusNode _languageFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _refreshFocusNode = FocusNode();
  final FocusNode _settingsFocusNode = FocusNode();
  final FocusNode _clearSearchFocusNode = FocusNode();

  final Map<String, int> _rowLastFocusedIndex = {
    'search': 0,
    'history': 0,
    'top': 0,
    'latest': 0,
    'comedy': 0,
  };
  final Map<String, List<FocusNode>> _rowFocusNodes = {
    'search': [],
    'history': [],
    'top': [],
    'latest': [],
    'comedy': [],
  };

  FocusNode _getFocusNode(String rowKey, int index) {
    final nodes = _rowFocusNodes[rowKey] ??= [];
    while (nodes.length <= index) {
      nodes.add(FocusNode());
    }
    return nodes[index];
  }

  List<String> get _visibleRowKeys {
    final keys = <String>[];
    if (_searchResults.isNotEmpty) keys.add('search');
    if (_history.isNotEmpty) keys.add('history');
    keys.add('top');
    keys.add('latest');
    keys.add('comedy');
    return keys;
  }

  int _getRowItemCount(String rowKey) {
    if (rowKey == 'search') {
      final hasLoadMore = _searchResults.isNotEmpty;
      return _searchResults.length + (hasLoadMore ? 1 : 0);
    }
    if (rowKey == 'history') {
      return _history.length;
    }
    final isTamil = _isTamilSelected;
    final list = rowKey == 'top'
        ? (isTamil ? _topTamil : _topEnglish)
        : rowKey == 'latest'
            ? (isTamil ? _latestTamil : _latestEnglish)
            : rowKey == 'comedy'
                ? (isTamil ? _comedyTamil : _comedyEnglish)
                : const <Movie>[];
    final hasLoadMore = list.isNotEmpty;
    return list.length + (hasLoadMore ? 1 : 0);
  }

  KeyEventResult _handleRowKeyNavigation(
    String rowKey,
    int index,
    int itemCount,
    RawKeyEvent event,
  ) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final visibleRows = _visibleRowKeys;
    final currentVisibleRowIndex = visibleRows.indexOf(rowKey);

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _getFocusNode(rowKey, index - 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < itemCount - 1) {
        _getFocusNode(rowKey, index + 1).requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (currentVisibleRowIndex >= 0 && currentVisibleRowIndex < visibleRows.length - 1) {
        final nextRowKey = visibleRows[currentVisibleRowIndex + 1];
        final nextRowCount = _getRowItemCount(nextRowKey);
        if (nextRowCount > 0) {
          var destIndex = _rowLastFocusedIndex[nextRowKey] ?? 0;
          if (destIndex >= nextRowCount) destIndex = nextRowCount - 1;
          _getFocusNode(nextRowKey, destIndex).requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (currentVisibleRowIndex > 0) {
        final prevRowKey = visibleRows[currentVisibleRowIndex - 1];
        final prevRowCount = _getRowItemCount(prevRowKey);
        if (prevRowCount > 0) {
          var destIndex = _rowLastFocusedIndex[prevRowKey] ?? 0;
          if (destIndex >= prevRowCount) destIndex = prevRowCount - 1;
          _getFocusNode(prevRowKey, destIndex).requestFocus();
          return KeyEventResult.handled;
        }
      } else if (currentVisibleRowIndex == 0) {
        if (rowKey == 'search' && _searchQuery.isNotEmpty) {
          _clearSearchFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        _languageFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _languageFocusNode.dispose();
    _searchFocusNode.dispose();
    _refreshFocusNode.dispose();
    _settingsFocusNode.dispose();
    _clearSearchFocusNode.dispose();

    for (final nodeList in _rowFocusNodes.values) {
      for (final node in nodeList) {
        node.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadHistory(),
        _fetchHomeMovies(),
      ]);

      if (mounted) {
        final initialList = _isTamilSelected ? _latestTamil : _latestEnglish;
        setState(() {
          _focusedMovie = initialList.isNotEmpty
              ? initialList.first
              : _history.isNotEmpty
                  ? _history.first
                  : null;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final visibleRows = _visibleRowKeys;
          if (visibleRows.isNotEmpty) {
            final firstRowKey = visibleRows.first;
            if (_getRowItemCount(firstRowKey) > 0) {
              _getFocusNode(firstRowKey, 0).requestFocus();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load movie catalogs: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchHomeMovies() async {
    _topTamilPage = 1;
    _latestTamilPage = 1;
    _comedyTamilPage = 1;
    _topEnglishPage = 1;
    _latestEnglishPage = 1;
    _comedyEnglishPage = 1;

    try {
      final results = await Future.wait([
        ApiClient.discoverMovies(language: 'ta', page: 1),
        ApiClient.getPopularMovies(language: 'ta', page: 1),
        ApiClient.discoverMovies(language: 'ta', genreId: 35, page: 1),
        ApiClient.discoverMovies(language: 'en', page: 1),
        ApiClient.getPopularMovies(language: 'en', page: 1),
        ApiClient.discoverMovies(language: 'en', genreId: 35, page: 1),
      ]);

      if (mounted) {
        setState(() {
          _latestTamil = results[0];
          _topTamil = results[1];
          _comedyTamil = results[2];

          _latestEnglish = results[3];
          _topEnglish = results[4];
          _comedyEnglish = results[5];
        });
      }
    } catch (e) {
      print('Fetch home movies failed: $e');
    }
  }

  Future<void> _loadHistory() async {
    final history = await LocalStorage.getHistory();
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _loadMoreTopTamil() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _topTamilPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'ta', page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _topTamilPage = nextPage;
        _topTamil.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreLatestTamil() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _latestTamilPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'ta', page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _latestTamilPage = nextPage;
        _latestTamil.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreComedyTamil() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _comedyTamilPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'ta', genreId: 35, page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _comedyTamilPage = nextPage;
        _comedyTamil.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreTopEnglish() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _topEnglishPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'en', page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _topEnglishPage = nextPage;
        _topEnglish.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreLatestEnglish() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _latestEnglishPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'en', page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _latestEnglishPage = nextPage;
        _latestEnglish.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreComedyEnglish() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _comedyEnglishPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'en', genreId: 35, page: nextPage);
    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _comedyEnglishPage = nextPage;
        _comedyEnglish.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreSearch() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _searchPage + 1;

    List<Movie> newMovies = [];
    if (_activeSearchText != null) {
      newMovies = await ApiClient.searchMovies(_activeSearchText!, page: nextPage);
    } else {
      final lang = _isTamilSelected ? 'ta' : 'en';
      newMovies = await ApiClient.discoverMovies(
        language: lang,
        year: _activeSearchYear,
        genreId: _activeSearchGenreId,
        page: nextPage,
      );
    }

    if (mounted && newMovies.isNotEmpty) {
      setState(() {
        _searchPage = nextPage;
        _searchResults.addAll(newMovies);
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _searchQuery = query.trim();
      _activeSearchText = query.trim();
      _activeSearchYear = null;
      _activeSearchGenreId = null;
      _searchPage = 1;
    });

    final results = await ApiClient.searchMovies(query, page: 1);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
        if (results.isNotEmpty) {
          _focusedMovie = results.first;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_searchResults.isNotEmpty) {
          _getFocusNode('search', 0).requestFocus();
        }
      });
    }
  }

  Future<void> _performDiscover(String label, {int? year, int? genreId}) async {
    setState(() {
      _isLoading = true;
      _searchQuery = label;
      _activeSearchText = null;
      _activeSearchYear = year;
      _activeSearchGenreId = genreId;
      _searchPage = 1;
    });

    final lang = _isTamilSelected ? 'ta' : 'en';
    final results = await ApiClient.discoverMovies(
      language: lang,
      year: year,
      genreId: genreId,
      page: 1,
    );

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
        if (results.isNotEmpty) {
          _focusedMovie = results.first;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_searchResults.isNotEmpty) {
          _getFocusNode('search', 0).requestFocus();
        }
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _activeSearchText = null;
      _activeSearchYear = null;
      _activeSearchGenreId = null;
      _searchResults.clear();
      _searchPage = 1;

      final currentList = _isTamilSelected ? _latestTamil : _latestEnglish;
      if (currentList.isNotEmpty) {
        _focusedMovie = currentList.first;
      } else if (_history.isNotEmpty) {
        _focusedMovie = _history.first;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final visibleRows = _visibleRowKeys;
      if (visibleRows.isNotEmpty) {
        final firstRow = visibleRows.first;
        if (_getRowItemCount(firstRow) > 0) {
          _getFocusNode(firstRow, 0).requestFocus();
        }
      }
    });
  }

  Widget _buildTopBarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    FocusNode? focusNode,
  }) {
    return Focus(
      focusNode: focusNode,
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final visibleRows = _visibleRowKeys;
            if (visibleRows.isNotEmpty) {
              final firstRowKey = visibleRows.first;
              if (firstRowKey == 'search' && _searchQuery.isNotEmpty) {
                _clearSearchFocusNode.requestFocus();
                return KeyEventResult.handled;
              }
              final maxCount = _getRowItemCount(firstRowKey);
              if (maxCount > 0) {
                var destIndex = _rowLastFocusedIndex[firstRowKey] ?? 0;
                if (destIndex >= maxCount) destIndex = maxCount - 1;
                _getFocusNode(firstRowKey, destIndex).requestFocus();
                return KeyEventResult.handled;
              }
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return Container(
            margin: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              color: focused ? TVTheme.accent : TVTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: IconButton(
              icon: Icon(icon, color: Colors.white),
              onPressed: onTap,
              tooltip: label,
            ),
          );
        },
      ),
    );
  }

  void _openMovieDetails(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsScreen(movie: movie),
      ),
    ).then((_) => _loadHistory());
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'StreamTV',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: TVTheme.accent,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_focusedMovie != null && _errorMessage == null)
                        SizedBox(
                          width: size.width * 0.5,
                          child: Text(
                            'Current: ${_focusedMovie!.title} (${_focusedMovie!.releaseDate.isNotEmpty ? _focusedMovie!.releaseDate.split('-')[0] : 'N/A'})${_focusedMovie!.genreTags.isNotEmpty ? '  •  ${_focusedMovie!.genreTags}' : ''}',
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildTopBarAction(
                        icon: Icons.language,
                        label: _isTamilSelected ? 'Tamil Cinema' : 'English Cinema',
                        focusNode: _languageFocusNode,
                        onTap: () {
                          setState(() {
                            _isTamilSelected = !_isTamilSelected;

                            _rowLastFocusedIndex['top'] = 0;
                            _rowLastFocusedIndex['latest'] = 0;
                            _rowLastFocusedIndex['comedy'] = 0;

                            for (final node in _rowFocusNodes['top'] ?? <FocusNode>[]) { node.dispose(); }
                            for (final node in _rowFocusNodes['latest'] ?? <FocusNode>[]) { node.dispose(); }
                            for (final node in _rowFocusNodes['comedy'] ?? <FocusNode>[]) { node.dispose(); }
                            _rowFocusNodes['top'] = [];
                            _rowFocusNodes['latest'] = [];
                            _rowFocusNodes['comedy'] = [];

                            final currentList = _isTamilSelected ? _latestTamil : _latestEnglish;
                            if (currentList.isNotEmpty) {
                              _focusedMovie = currentList.first;
                            } else if (_history.isNotEmpty) {
                              _focusedMovie = _history.first;
                            } else {
                              _focusedMovie = null;
                            }
                          });
                        },
                      ),
                      _buildTopBarAction(
                        icon: Icons.search,
                        label: 'Search Movies',
                        focusNode: _searchFocusNode,
                        onTap: () => SearchDialog.show(
                          context: context,
                          onSearch: _performSearch,
                          onDiscover: _performDiscover,
                        ),
                      ),
                      _buildTopBarAction(
                        icon: Icons.refresh,
                        label: 'Refresh',
                        focusNode: _refreshFocusNode,
                        onTap: _loadAllData,
                      ),
                      _buildTopBarAction(
                        icon: Icons.settings,
                        label: 'Server Settings',
                        focusNode: _settingsFocusNode,
                        onTap: () => SettingsDialog.show(
                          context: context,
                          onSaved: _loadAllData,
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: TVTheme.accent),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: TVTheme.accent),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 40),
                          children: [
                            if (_searchResults.isNotEmpty)
                              MovieLane(
                                rowKey: 'search',
                                title: 'Search Results: "$_searchQuery"',
                                movies: _searchResults,
                                onMovieTap: _openMovieDetails,
                                onMovieFocused: (m) => setState(() => _focusedMovie = m),
                                onLoadMore: _loadMoreSearch,
                                onClear: _clearSearch,
                                clearFocusNode: _clearSearchFocusNode,
                                getFocusNode: _getFocusNode,
                                onKeyNav: _handleRowKeyNavigation,
                                onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                              ),
                            if (_history.isNotEmpty)
                              MovieLane(
                                rowKey: 'history',
                                title: 'Recently Watched',
                                movies: _history,
                                onMovieTap: _openMovieDetails,
                                onMovieFocused: (m) => setState(() => _focusedMovie = m),
                                getFocusNode: _getFocusNode,
                                onKeyNav: _handleRowKeyNavigation,
                                onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                              ),
                            MovieLane(
                              rowKey: 'latest',
                              title: _isTamilSelected ? 'Latest Tamil Releases' : 'Latest Releases',
                              movies: _isTamilSelected ? _latestTamil : _latestEnglish,
                              onMovieTap: _openMovieDetails,
                              onMovieFocused: (m) => setState(() => _focusedMovie = m),
                              onLoadMore: _isTamilSelected ? _loadMoreLatestTamil : _loadMoreLatestEnglish,
                              getFocusNode: _getFocusNode,
                              onKeyNav: _handleRowKeyNavigation,
                              onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                            ),
                            MovieLane(
                              rowKey: 'top',
                              title: _isTamilSelected ? 'Popular Tamil Movies' : 'Popular Movies',
                              movies: _isTamilSelected ? _topTamil : _topEnglish,
                              onMovieTap: _openMovieDetails,
                              onMovieFocused: (m) => setState(() => _focusedMovie = m),
                              onLoadMore: _isTamilSelected ? _loadMoreTopTamil : _loadMoreTopEnglish,
                              getFocusNode: _getFocusNode,
                              onKeyNav: _handleRowKeyNavigation,
                              onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                            ),
                            MovieLane(
                              rowKey: 'comedy',
                              title: _isTamilSelected ? 'Tamil Comedy Hits' : 'Comedy Hits',
                              movies: _isTamilSelected ? _comedyTamil : _comedyEnglish,
                              onMovieTap: _openMovieDetails,
                              onMovieFocused: (m) => setState(() => _focusedMovie = m),
                              onLoadMore: _isTamilSelected ? _loadMoreComedyTamil : _loadMoreComedyEnglish,
                              getFocusNode: _getFocusNode,
                              onKeyNav: _handleRowKeyNavigation,
                              onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
