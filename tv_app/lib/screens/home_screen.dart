import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';
import 'details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Movie> _history = [];
  
  // Tamil screen lists
  List<Movie> _topTamil = [];
  List<Movie> _latestTamil = [];
  List<Movie> _comedyTamil = [];
  
  // English screen lists
  List<Movie> _topEnglish = [];
  List<Movie> _latestEnglish = [];
  List<Movie> _comedyEnglish = [];
  
  List<Movie> _searchResults = [];
  
  Movie? _focusedMovie;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isTamilSelected = true;
  
  // Search & Pagination states
  String _searchQuery = "";
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

  // Focus tracking maps for row-to-row traversal
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

  KeyEventResult _handleRowKeyNavigation(
    String rowKey,
    int index,
    int itemCount,
    RawKeyEvent event,
  ) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;

    final visibleRows = _visibleRowKeys;
    final rowPos = visibleRows.indexOf(rowKey);

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (rowPos > 0) {
        final prevRowKey = visibleRows[rowPos - 1];
        final destIndex = _rowLastFocusedIndex[prevRowKey] ?? 0;
        final targetNode = _getFocusNode(prevRowKey, destIndex);
        targetNode.requestFocus();
        return KeyEventResult.handled;
      }
      // If we are on the first row, let arrowUp traverse naturally to the top bar
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (rowPos >= 0 && rowPos < visibleRows.length - 1) {
        final nextRowKey = visibleRows[rowPos + 1];
        final destIndex = _rowLastFocusedIndex[nextRowKey] ?? 0;
        final targetNode = _getFocusNode(nextRowKey, destIndex);
        targetNode.requestFocus();
        return KeyEventResult.handled;
      }
      // If we are on the last row, consume arrowDown to prevent focus escaping
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (index == 0) {
        // Prevent going left past the first item (prevents jumping rows)
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (index == itemCount - 1) {
        // Prevent going right past the last item (prevents jumping rows)
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _rowFocusNodes.values.forEach((list) {
      for (var node in list) {
        node.dispose();
      }
    });
    _ipController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _topTamilPage = 1;
      _latestTamilPage = 1;
      _comedyTamilPage = 1;
      _topEnglishPage = 1;
      _latestEnglishPage = 1;
      _comedyEnglishPage = 1;
      _searchPage = 1;
      _searchResults = [];
      _searchQuery = "";

      _rowLastFocusedIndex['search'] = 0;
      _rowLastFocusedIndex['history'] = 0;
      _rowLastFocusedIndex['top'] = 0;
      _rowLastFocusedIndex['latest'] = 0;
      _rowLastFocusedIndex['comedy'] = 0;

      _rowFocusNodes.values.forEach((list) {
        for (var node in list) {
          node.dispose();
        }
      });
      _rowFocusNodes['search'] = [];
      _rowFocusNodes['history'] = [];
      _rowFocusNodes['top'] = [];
      _rowFocusNodes['latest'] = [];
      _rowFocusNodes['comedy'] = [];
    });
    
    await _fetchHomeMovies();
  }

  Future<void> _fetchHomeMovies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _topTamilPage = 1;
      _latestTamilPage = 1;
      _comedyTamilPage = 1;
      _topEnglishPage = 1;
      _latestEnglishPage = 1;
      _comedyEnglishPage = 1;
      _searchPage = 1;
      _searchResults = [];
      _searchQuery = "";
    });
    
    try {
      // Load local history
      final history = await LocalStorage.getHistory();
      
      // Load Tamil lists
      final topTamilList = await ApiClient.getPopularMovies(language: 'ta-IN', page: 1);
      final latestTamilList = await ApiClient.discoverMovies(language: 'ta-IN', page: 1);
      final comedyTamilList = await ApiClient.discoverMovies(language: 'ta-IN', genreId: 35, page: 1);
      
      // Load English lists
      final topEnglishList = await ApiClient.getPopularMovies(language: 'en-US', page: 1);
      final latestEnglishList = await ApiClient.discoverMovies(language: 'en-US', page: 1);
      final comedyEnglishList = await ApiClient.discoverMovies(language: 'en-US', genreId: 35, page: 1);

      setState(() {
        _history = history;
        _topTamil = topTamilList;
        _latestTamil = latestTamilList;
        _comedyTamil = comedyTamilList;
        
        _topEnglish = topEnglishList;
        _latestEnglish = latestEnglishList;
        _comedyEnglish = comedyEnglishList;
        
        _isLoading = false;
        
        // If remote queries returned nothing, it indicates a connection issue
        if (topTamilList.isEmpty && topEnglishList.isEmpty) {
          _errorMessage = "Connection Error: Unable to reach the backend server at '${ApiClient.baseUrl}'.";
          _showSettingsDialog();
        }
        
        // Default focused movie based on initial language (Tamil)
        final currentList = _isTamilSelected ? latestTamilList : latestEnglishList;
        if (currentList.isNotEmpty) {
          _focusedMovie = currentList.first;
        } else if (history.isNotEmpty) {
          _focusedMovie = history.first;
        } else {
          _focusedMovie = null;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Connection Error: $e";
      });
      _showSettingsDialog();
    }
  }

  // Load history silently (when returning from Details page)
  Future<void> _loadHistory() async {
    final history = await LocalStorage.getHistory();
    setState(() {
      _history = history;
    });
  }

  Future<void> _loadMoreTopTamil() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _topTamilPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'ta-IN', page: nextPage);
    setState(() {
      _topTamil.addAll(newMovies);
      _topTamilPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreLatestTamil() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _latestTamilPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'ta-IN', page: nextPage);
    setState(() {
      _latestTamil.addAll(newMovies);
      _latestTamilPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreComedyTamil() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _comedyTamilPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'ta-IN', genreId: 35, page: nextPage);
    setState(() {
      _comedyTamil.addAll(newMovies);
      _comedyTamilPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreTopEnglish() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _topEnglishPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'en-US', page: nextPage);
    setState(() {
      _topEnglish.addAll(newMovies);
      _topEnglishPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreLatestEnglish() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _latestEnglishPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'en-US', page: nextPage);
    setState(() {
      _latestEnglish.addAll(newMovies);
      _latestEnglishPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreComedyEnglish() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _comedyEnglishPage + 1;
    final newMovies = await ApiClient.discoverMovies(language: 'en-US', genreId: 35, page: nextPage);
    setState(() {
      _comedyEnglish.addAll(newMovies);
      _comedyEnglishPage = nextPage;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreSearch() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    final nextPage = _searchPage + 1;
    List<Movie> newMovies = [];

    if (_activeSearchText != null) {
      newMovies = await ApiClient.searchMovies(_activeSearchText!, page: nextPage);
    } else {
      final results = await Future.wait([
        ApiClient.discoverMovies(
          language: 'ta-IN',
          year: _activeSearchYear,
          genreId: _activeSearchGenreId,
          page: nextPage,
        ),
        ApiClient.discoverMovies(
          language: 'en-US',
          year: _activeSearchYear,
          genreId: _activeSearchGenreId,
          page: nextPage,
        ),
      ]);
      final List<Movie> combined = [...results[0], ...results[1]];
      final seen = <int>{};
      newMovies = combined.where((m) => seen.add(m.tmdbId)).toList();
    }

    setState(() {
      _searchResults.addAll(newMovies);
      _searchPage = nextPage;
      _isLoadingMore = false;
    });
  }

  // Search Movies Flow
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _searchQuery = query;
      _searchPage = 1;
      _activeSearchText = query;
      _activeSearchYear = null;
      _activeSearchGenreId = null;
      
      _rowLastFocusedIndex['search'] = 0;
      _rowFocusNodes['search']?.forEach((node) => node.dispose());
      _rowFocusNodes['search'] = [];
    });

    final results = await ApiClient.searchMovies(query);
    setState(() {
      _searchResults = results;
      _isLoading = false;
      if (results.isNotEmpty) {
        _focusedMovie = results.first;
      }
    });
  }

  // Discover movies filterable by genre or year for Quick Tags (Querying Tamil and English parallelly)
  Future<void> _performDiscover(String label, {int? year, int? genreId}) async {
    setState(() {
      _isLoading = true;
      _searchQuery = label;
      _searchPage = 1;
      _activeSearchText = null;
      _activeSearchYear = year;
      _activeSearchGenreId = genreId;

      _rowLastFocusedIndex['search'] = 0;
      _rowFocusNodes['search']?.forEach((node) => node.dispose());
      _rowFocusNodes['search'] = [];
    });

    final results = await Future.wait([
      ApiClient.discoverMovies(language: 'ta-IN', year: year, genreId: genreId),
      ApiClient.discoverMovies(language: 'en-US', year: year, genreId: genreId),
    ]);

    final List<Movie> combined = [...results[0], ...results[1]];
    final seen = <int>{};
    final unique = combined.where((m) => seen.add(m.tmdbId)).toList();

    setState(() {
      _searchResults = unique;
      _isLoading = false;
      if (unique.isNotEmpty) {
        _focusedMovie = unique.first;
      }
    });
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = "";
      _searchResults = [];
      _searchPage = 1;
      _activeSearchText = null;
      _activeSearchYear = null;
      _activeSearchGenreId = null;

      _rowLastFocusedIndex['search'] = 0;
      _rowFocusNodes['search']?.forEach((node) => node.dispose());
      _rowFocusNodes['search'] = [];
      
      final currentList = _isTamilSelected ? _latestTamil : _latestEnglish;
      if (currentList.isNotEmpty) {
        _focusedMovie = currentList.first;
      } else if (_history.isNotEmpty) {
        _focusedMovie = _history.first;
      } else {
        _focusedMovie = null;
      }
    });
  }

  Widget _buildSearchTag(BuildContext context, String label, VoidCallback onTap, {bool isLeftMost = false, FocusNode? leftFocusNode}) {
    return Focus(
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            Navigator.pop(context);
            onTap();
            return KeyEventResult.handled;
          }
          if (isLeftMost && event.logicalKey == LogicalKeyboardKey.arrowLeft && leftFocusNode != null) {
            leftFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return ActionChip(
            backgroundColor: focused ? Colors.white : TVTheme.surface,
            label: Text(
              label,
              style: TextStyle(
                color: focused ? Colors.black : Colors.white,
                fontWeight: focused ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: focused ? Colors.white : Colors.grey.shade800,
                width: 1,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              onTap();
            },
          );
        },
      ),
    );
  }

  // Open Search Query input dialog with focusable Quick Search tags
  void _showSearchDialog() {
    _searchController.clear();
    final textFieldFocusNode = FocusNode();
    final cancelButtonFocusNode = FocusNode();
    final searchButtonFocusNode = FocusNode();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: TVTheme.surface,
          title: const Text('Search Movies'),
          content: SizedBox(
            width: 750, // Wider for side-by-side split screen
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Left Column: Custom Text Input & Search/Cancel Buttons
                SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Type Movie Title',
                        style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Focus(
                        onKey: (node, event) {
                          if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            searchButtonFocusNode.requestFocus();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          focusNode: textFieldFocusNode,
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Enter title...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (val) {
                            Future.delayed(const Duration(milliseconds: 150), () {
                              if (searchButtonFocusNode.canRequestFocus) {
                                searchButtonFocusNode.requestFocus();
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Focus(
                              focusNode: cancelButtonFocusNode,
                              onKey: (node, event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                    textFieldFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                                    searchButtonFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey == LogicalKeyboardKey.select ||
                                      event.logicalKey == LogicalKeyboardKey.enter ||
                                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                      event.logicalKey == LogicalKeyboardKey.space) {
                                    Navigator.pop(context);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return TextButton(
                                    style: TextButton.styleFrom(
                                      backgroundColor: focused ? Colors.white.withOpacity(0.15) : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Focus(
                              focusNode: searchButtonFocusNode,
                              onKey: (node, event) {
                                if (event is RawKeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                    textFieldFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                    cancelButtonFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey == LogicalKeyboardKey.select ||
                                      event.logicalKey == LogicalKeyboardKey.enter ||
                                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                      event.logicalKey == LogicalKeyboardKey.space) {
                                    Navigator.pop(context);
                                    _performSearch(_searchController.text);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final focused = Focus.of(context).hasFocus;
                                  return ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _performSearch(_searchController.text);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: focused ? Colors.white : TVTheme.accent,
                                      foregroundColor: focused ? Colors.black : Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    child: const Text('Search'),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Vertical Divider
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: SizedBox(
                    height: 280,
                    child: VerticalDivider(color: Colors.grey, width: 1, thickness: 1),
                  ),
                ),
                
                // Right Column: All Quick Search Tags (Scrollable list of Genres and Years)
                Expanded(
                  child: SizedBox(
                    height: 280,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Search Genres',
                            style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildSearchTag(context, 'Action', () => _performDiscover('Action', genreId: 28), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                              _buildSearchTag(context, 'Comedy', () => _performDiscover('Comedy', genreId: 35)),
                              _buildSearchTag(context, 'Thriller', () => _performDiscover('Thriller', genreId: 53)),
                              _buildSearchTag(context, 'Horror', () => _performDiscover('Horror', genreId: 27)),
                              _buildSearchTag(context, 'Sci-Fi', () => _performDiscover('Sci-Fi', genreId: 878), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                              _buildSearchTag(context, 'Romance', () => _performDiscover('Romance', genreId: 10749)),
                              _buildSearchTag(context, 'Animation', () => _performDiscover('Animation', genreId: 16)),
                              _buildSearchTag(context, 'Drama', () => _performDiscover('Drama', genreId: 18), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Quick Search Years',
                            style: TextStyle(color: TVTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildSearchTag(context, '2026', () => _performDiscover('2026', year: 2026), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                              _buildSearchTag(context, '2025', () => _performDiscover('2025', year: 2025)),
                              _buildSearchTag(context, '2024', () => _performDiscover('2024', year: 2024)),
                              _buildSearchTag(context, '2023', () => _performDiscover('2023', year: 2023)),
                              _buildSearchTag(context, '2022', () => _performDiscover('2022', year: 2022)),
                              _buildSearchTag(context, '2021', () => _performDiscover('2021', year: 2021), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                              _buildSearchTag(context, '2020', () => _performDiscover('2020', year: 2020)),
                              _buildSearchTag(context, '2019', () => _performDiscover('2019', year: 2019)),
                              _buildSearchTag(context, '2018', () => _performDiscover('2018', year: 2018)),
                              _buildSearchTag(context, '2015', () => _performDiscover('2015', year: 2015)),
                              _buildSearchTag(context, '2010', () => _performDiscover('2010', year: 2010), isLeftMost: true, leftFocusNode: searchButtonFocusNode),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      textFieldFocusNode.dispose();
      cancelButtonFocusNode.dispose();
      searchButtonFocusNode.dispose();
    });
  }

  // Open API server settings modal (TV D-pad focus trap resolved)
  void _showSettingsDialog() {
    _ipController.text = ApiClient.baseUrl;
    final textFieldFocusNode = FocusNode();
    final cancelFocusNode = FocusNode();
    final saveFocusNode = FocusNode();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: TVTheme.surface,
          title: const Text('Backend API Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Specify the server IP and port where the FastAPI python server is running.',
                style: TextStyle(color: TVTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Focus(
                onKey: (node, event) {
                  if (event is RawKeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      // D-pad down from text field focuses Save Settings button
                      saveFocusNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  focusNode: textFieldFocusNode,
                  autofocus: true,
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Server Base URL',
                    hintText: 'e.g., http://192.168.29.50:8000/api/v1',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (val) {
                    // Auto focus Save button when 'Done/OK' is pressed on virtual keyboard
                    // Wrapped in Future.delayed to bypass Android keyboard dismissal focus resets
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (saveFocusNode.canRequestFocus) {
                        saveFocusNode.requestFocus();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          actions: [
            Focus(
              focusNode: cancelFocusNode,
              onKey: (node, event) {
                if (event is RawKeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    textFieldFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    saveFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    Navigator.pop(context);
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: focused ? Colors.white.withOpacity(0.1) : Colors.transparent,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  );
                },
              ),
            ),
            Focus(
              focusNode: saveFocusNode,
              onKey: (node, event) {
                if (event is RawKeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    textFieldFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    cancelFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                      event.logicalKey == LogicalKeyboardKey.space) {
                    () async {
                      await ApiClient.setBaseUrl(_ipController.text);
                      Navigator.pop(context);
                      _loadAllData();
                    }();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focused ? Colors.white : TVTheme.accent,
                      foregroundColor: focused ? Colors.black : Colors.white,
                    ),
                    onPressed: () async {
                      await ApiClient.setBaseUrl(_ipController.text);
                      Navigator.pop(context);
                      _loadAllData();
                    },
                    child: const Text('Save Settings'),
                  );
                },
              ),
            )
          ],
        );
      },
    ).then((_) {
      textFieldFocusNode.dispose();
      cancelFocusNode.dispose();
      saveFocusNode.dispose();
    });
  }

  Widget _buildMovieRow(String rowKey, String title, List<Movie> movies, {VoidCallback? onLoadMore, bool showClear = false}) {
    if (movies.isEmpty && !showClear) return const SizedBox.shrink();
    
    // Add 1 extra item for the focusable "Load More" card if pagination is available
    final hasLoadMore = onLoadMore != null && movies.isNotEmpty;
    final itemCount = movies.length + (hasLoadMore ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (showClear)
                Padding(
                  padding: const EdgeInsets.only(right: 24.0),
                  child: Focus(
                    onKey: (node, event) {
                      if (event is RawKeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                            event.logicalKey == LogicalKeyboardKey.space) {
                          _clearSearch();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasFocus;
                        return TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: focused ? TVTheme.accent : Colors.transparent,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Clear Search', style: TextStyle(fontSize: 12)),
                          onPressed: _clearSearch,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: movies.isEmpty && showClear
              ? const Center(
                  child: Text(
                    'No search results found.',
                    style: TextStyle(color: TVTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    // Check if this is the last item and we have a load-more option
                    if (hasLoadMore && index == movies.length) {
                      final node = _getFocusNode(rowKey, index);
                      return Focus(
                        focusNode: node,
                        onFocusChange: (focused) {
                          if (focused) {
                            setState(() {
                              _rowLastFocusedIndex[rowKey] = index;
                            });
                            if (node.context != null) {
                              Scrollable.ensureVisible(
                                node.context!,
                                duration: const Duration(milliseconds: 300),
                                alignment: 0.5,
                                curve: Curves.easeInOut,
                              );
                            }
                          }
                        },
                        onKey: (node, event) {
                          final navResult = _handleRowKeyNavigation(rowKey, index, itemCount, event);
                          if (navResult != KeyEventResult.ignored) {
                            return navResult;
                          }
                          if (event is RawKeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                event.logicalKey == LogicalKeyboardKey.space) {
                              onLoadMore();
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Builder(
                          builder: (context) {
                            final focused = Focus.of(context).hasFocus;
                            return GestureDetector(
                              onTap: onLoadMore,
                              child: Container(
                                width: 130,
                                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                decoration: TVTheme.focusDecoration(focused),
                                child: Card(
                                  color: TVTheme.surface,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isLoadingMore ? Icons.hourglass_empty : Icons.arrow_forward,
                                        color: focused ? Colors.white : TVTheme.accent,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _isLoadingMore ? 'Loading...' : 'Load More',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }

                    final movie = movies[index];
                    final node = _getFocusNode(rowKey, index);
                    return MovieCard(
                      movie: movie,
                      focusNode: node,
                      onKey: (node, event) {
                        return _handleRowKeyNavigation(rowKey, index, itemCount, event);
                      },
                      onFocusChanged: (hasFocus) {
                        if (hasFocus) {
                          setState(() {
                            _focusedMovie = movie;
                            _rowLastFocusedIndex[rowKey] = index;
                          });
                          if (node.context != null) {
                            Scrollable.ensureVisible(
                              node.context!,
                              duration: const Duration(milliseconds: 300),
                              alignment: 0.5,
                              curve: Curves.easeInOut,
                            );
                          }
                        }
                      },
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DetailsScreen(movie: movie),
                          ),
                        ).then((_) => _loadHistory()); // Silently refresh history list on return
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // D-pad focus-aware action buttons for TV top-bar
  Widget _buildTopBarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Focus(
      onKey: (node, event) {
        if (event is RawKeyDownEvent) {
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

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar / Title & Search/Settings Buttons
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
                        Text(
                          'Current: ${_focusedMovie!.title} (${_focusedMovie!.releaseDate.split('-')[0]})',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildTopBarAction(
                        icon: Icons.language,
                        label: _isTamilSelected ? 'Tamil Cinema' : 'English Cinema',
                        onTap: () {
                          setState(() {
                            _isTamilSelected = !_isTamilSelected;

                            _rowLastFocusedIndex['top'] = 0;
                            _rowLastFocusedIndex['latest'] = 0;
                            _rowLastFocusedIndex['comedy'] = 0;

                            _rowFocusNodes['top']?.forEach((node) => node.dispose());
                            _rowFocusNodes['latest']?.forEach((node) => node.dispose());
                            _rowFocusNodes['comedy']?.forEach((node) => node.dispose());
                            _rowFocusNodes['top'] = [];
                            _rowFocusNodes['latest'] = [];
                            _rowFocusNodes['comedy'] = [];

                            // Update focused movie on category change
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
                        onTap: _showSearchDialog,
                      ),
                      _buildTopBarAction(
                        icon: Icons.refresh,
                        label: 'Refresh',
                        onTap: _loadAllData,
                      ),
                      _buildTopBarAction(
                        icon: Icons.settings,
                        label: 'Server Settings',
                        onTap: _showSettingsDialog,
                      ),
                    ],
                  )
                ],
              ),
            ),

            // Loader / Error Banner / Main Lanes
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: TVTheme.accent))
                  : _errorMessage != null
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            margin: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: TVTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade900, width: 2),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: TVTheme.accent, size: 64),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Please verify that your python backend is running and that your TV/Phone is connected to the same Wi-Fi network.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: TVTheme.textSecondary, fontSize: 13),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Focus(
                                      autofocus: true,
                                      onKey: (node, event) {
                                        if (event is RawKeyDownEvent) {
                                          if (event.logicalKey == LogicalKeyboardKey.select ||
                                              event.logicalKey == LogicalKeyboardKey.enter ||
                                              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                              event.logicalKey == LogicalKeyboardKey.space) {
                                            _loadAllData();
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final focused = Focus.of(context).hasFocus;
                                          return ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: focused ? Colors.white : TVTheme.accent,
                                              foregroundColor: focused ? Colors.black : Colors.white,
                                            ),
                                            onPressed: _loadAllData,
                                            icon: const Icon(Icons.refresh),
                                            label: const Text('Try Again'),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Focus(
                                      onKey: (node, event) {
                                        if (event is RawKeyDownEvent) {
                                          if (event.logicalKey == LogicalKeyboardKey.select ||
                                              event.logicalKey == LogicalKeyboardKey.enter ||
                                              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                              event.logicalKey == LogicalKeyboardKey.space) {
                                            _showSettingsDialog();
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        return KeyEventResult.ignored;
                                      },
                                      child: Builder(
                                        builder: (context) {
                                          final focused = Focus.of(context).hasFocus;
                                          return ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: focused ? Colors.white : Colors.grey.shade800,
                                              foregroundColor: focused ? Colors.black : Colors.white,
                                            ),
                                            onPressed: _showSettingsDialog,
                                            icon: const Icon(Icons.settings),
                                            label: const Text('Configure Server'),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Quick Movie Description Block
                              if (_focusedMovie != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                                  child: SizedBox(
                                    width: size.width * 0.6,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _focusedMovie!.title,
                                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: TVTheme.surface,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'IMDb ${_focusedMovie!.voteAverage.toStringAsFixed(1)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              _focusedMovie!.releaseDate.split('-')[0],
                                              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _focusedMovie!.overview,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: TVTheme.textSecondary, fontSize: 12, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              
                              const SizedBox(height: 20),

                              // Search results row (Tamil & English combined)
                              _buildMovieRow('search', 'Search Results for "$_searchQuery"', _searchResults, onLoadMore: _loadMoreSearch, showClear: _searchQuery.isNotEmpty),
                              
                              _buildMovieRow('history', 'Resume Watching', _history),
                              
                              if (_isTamilSelected) ...[
                                _buildMovieRow('top', 'Top Tamil Movies', _topTamil, onLoadMore: _loadMoreTopTamil),
                                _buildMovieRow('latest', 'Latest Tamil Movies', _latestTamil, onLoadMore: _loadMoreLatestTamil),
                                _buildMovieRow('comedy', 'Tamil Comedy Movies', _comedyTamil, onLoadMore: _loadMoreComedyTamil),
                              ] else ...[
                                _buildMovieRow('top', 'Top English Movies', _topEnglish, onLoadMore: _loadMoreTopEnglish),
                                _buildMovieRow('latest', 'Latest English Movies', _latestEnglish, onLoadMore: _loadMoreLatestEnglish),
                                _buildMovieRow('comedy', 'English Comedy Movies', _comedyEnglish, onLoadMore: _loadMoreComedyEnglish),
                              ],
                              
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
