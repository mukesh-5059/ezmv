import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../models/dashboard_lane.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import '../widgets/movie_lane.dart';
import '../widgets/search_dialog.dart';
import '../widgets/settings_dialog.dart';
import 'details_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Movie> _history = [];
  List<DashboardLane> _lanes = [];

  List<Movie> _searchResults = [];

  Movie? _focusedMovie;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isTamilSelected = true;

  String _searchQuery = '';
  int _searchPage = 1;

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
  };
  final Map<String, List<FocusNode>> _rowFocusNodes = {
    'search': [],
    'history': [],
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
    for (final lane in _lanes) {
      keys.add(lane.id);
    }
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
    final lane = _lanes.cast<DashboardLane?>().firstWhere(
      (l) => l?.id == rowKey,
      orElse: () => null,
    );
    if (lane != null) {
      return lane.items.length + (lane.hasMore ? 1 : 0);
    }
    return 0;
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
        Movie? initialMovie;
        if (_lanes.isNotEmpty && _lanes.first.items.isNotEmpty) {
          initialMovie = _lanes.first.items.first;
        } else if (_history.isNotEmpty) {
          initialMovie = _history.first;
        }

        setState(() {
          _focusedMovie = initialMovie;
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
    try {
      final lanes = await ApiClient.getDashboard(language: _isTamilSelected ? 'ta' : 'en');
      if (mounted) {
        setState(() {
          _lanes = lanes;
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

  Future<void> _loadMoreLane(DashboardLane lane) async {
    if (_isLoadingMore || !lane.hasMore || lane.nextPage == null) return;
    _isLoadingMore = true;
    final lang = _isTamilSelected ? 'ta' : 'en';
    final res = await ApiClient.getDashboardLane(
      laneId: lane.id,
      language: lang,
      page: lane.nextPage!,
    );
    if (mounted && res != null) {
      final rawItems = res['items'] as List? ?? [];
      final newMovies = rawItems.map((e) => Movie.fromJson(e)).toList();
      if (newMovies.isNotEmpty) {
        setState(() {
          lane.items.addAll(newMovies);
          lane.hasMore = res['has_more'] ?? false;
          lane.nextPage = res['next_page'];
        });
      } else {
        setState(() {
          lane.hasMore = false;
          lane.nextPage = null;
        });
      }
    }
    _isLoadingMore = false;
  }

  Future<void> _loadMoreSearch() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    final nextPage = _searchPage + 1;

    List<Movie> newMovies = [];
    if (_activeSearchText != null) {
      newMovies = await ApiClient.searchMovies(query: _activeSearchText!, page: nextPage);
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

    final results = await ApiClient.searchMovies(query: query, page: 1);
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

      if (_lanes.isNotEmpty && _lanes.first.items.isNotEmpty) {
        _focusedMovie = _lanes.first.items.first;
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
                        'EzMV',
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

                            for (final nodes in _rowFocusNodes.values) {
                              for (final node in nodes) {
                                node.dispose();
                              }
                            }
                            _rowFocusNodes.clear();
                            _rowLastFocusedIndex.clear();
                          });
                          _loadAllData();
                        },
                      ),
                      _buildTopBarAction(
                        icon: Icons.search,
                        label: 'Search Movies',
                        focusNode: _searchFocusNode,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SearchScreen()),
                          );
                        },
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
                            ..._lanes.map(
                              (lane) => MovieLane(
                                key: ValueKey('${lane.id}_${_isTamilSelected ? 'ta' : 'en'}'),
                                rowKey: lane.id,
                                title: lane.title,
                                movies: lane.items,
                                onMovieTap: _openMovieDetails,
                                onMovieFocused: (m) => setState(() => _focusedMovie = m),
                                onLoadMore: lane.hasMore ? () => _loadMoreLane(lane) : null,
                                getFocusNode: _getFocusNode,
                                onKeyNav: _handleRowKeyNavigation,
                                onFocusedIndexChanged: (key, idx) => _rowLastFocusedIndex[key] = idx,
                              ),
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
