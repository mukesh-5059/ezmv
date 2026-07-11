import 'package:flutter/material.dart';
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
  List<Movie> _latestTamil = [];
  List<Movie> _tamil = [];
  List<Movie> _popular = [];
  List<Movie> _searchResults = [];
  
  Movie? _focusedMovie;
  bool _isLoading = true;
  String? _errorMessage;
  
  // Search & Pagination states
  String _searchQuery = "";
  int _latestTamilPage = 1;
  int _tamilPage = 1;
  int _popularPage = 1;
  bool _isLoadingMore = false;

  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _latestTamilPage = 1;
      _tamilPage = 1;
      _popularPage = 1;
      _searchResults = [];
      _searchQuery = "";
    });
    
    try {
      // Load local history
      final history = await LocalStorage.getHistory();
      
      // Load remote Tamil (latest & popular) & Popular movies (page 1)
      final latestTamilList = await ApiClient.discoverMovies(language: 'ta-IN', page: 1);
      final tamilList = await ApiClient.getPopularMovies(language: 'ta-IN', page: 1);
      final popularList = await ApiClient.getPopularMovies(language: 'en-US', page: 1);

      setState(() {
        _history = history;
        _latestTamil = latestTamilList;
        _tamil = tamilList;
        _popular = popularList;
        _isLoading = false;
        
        // If remote queries returned nothing, it indicates a connection issue
        if (latestTamilList.isEmpty && tamilList.isEmpty && popularList.isEmpty) {
          _errorMessage = "Connection Error: Unable to reach the backend server at '${ApiClient.baseUrl}'.";
        }
        
        // Default focused movie to the first Latest Tamil item
        if (latestTamilList.isNotEmpty) {
          _focusedMovie = latestTamilList.first;
        } else if (tamilList.isNotEmpty) {
          _focusedMovie = tamilList.first;
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
    }
  }

  // Load history silently (when returning from Details page)
  Future<void> _loadHistory() async {
    final history = await LocalStorage.getHistory();
    setState(() {
      _history = history;
    });
  }

  // Paginate Latest Tamil Movies
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

  // Paginate Tamil Movies
  Future<void> _loadMoreTamil() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    
    final nextPage = _tamilPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'ta-IN', page: nextPage);
    
    setState(() {
      _tamil.addAll(newMovies);
      _tamilPage = nextPage;
      _isLoadingMore = false;
    });
  }

  // Paginate Popular Movies
  Future<void> _loadMorePopular() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    
    final nextPage = _popularPage + 1;
    final newMovies = await ApiClient.getPopularMovies(language: 'en-US', page: nextPage);
    
    setState(() {
      _popular.addAll(newMovies);
      _popularPage = nextPage;
      _isLoadingMore = false;
    });
  }

  // Search Movies Flow
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _searchQuery = query;
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

  void _clearSearch() {
    setState(() {
      _searchResults = [];
      _searchQuery = "";
      if (_tamil.isNotEmpty) {
        _focusedMovie = _tamil.first;
      }
    });
  }

  // Open Search Query input dialog
  void _showSearchDialog() {
    _searchController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: TVTheme.surface,
          title: const Text('Search Movies'),
          content: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter movie title...',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (val) {
              Navigator.pop(context);
              _performSearch(val);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _performSearch(_searchController.text);
              },
              style: ElevatedButton.styleFrom(backgroundColor: TVTheme.accent),
              child: const Text('Search'),
            )
          ],
        );
      },
    );
  }

  // Open API server settings modal
  void _showSettingsDialog() {
    _ipController.text = ApiClient.baseUrl;
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
              TextField(
                controller: _ipController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Server Base URL',
                  hintText: 'e.g., http://192.168.29.50:8000/api/v1',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            Focus(
              child: Builder(
                builder: (context) {
                  final focused = Focus.of(context).hasFocus;
                  return TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: focused ? Colors.white.withOpacity(0.1) : Colors.transparent,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  );
                },
              ),
            ),
            Focus(
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
    );
  }

  Widget _buildMovieRow(String title, List<Movie> movies, {VoidCallback? onLoadMore, bool showClear = false}) {
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
                      return Focus(
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
                    return MovieCard(
                      movie: movie,
                      onFocusChanged: (hasFocus) {
                        if (hasFocus) {
                          setState(() {
                            _focusedMovie = movie;
                          });
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

                              // Lanes (Tamil Cinema placed at the top of remote lanes)
                              _buildMovieRow('Search Results for "$_searchQuery"', _searchResults, showClear: _searchQuery.isNotEmpty),
                              _buildMovieRow('Resume Watching', _history),
                              _buildMovieRow('Latest Tamil Movies', _latestTamil, onLoadMore: _loadMoreLatestTamil),
                              _buildMovieRow('Tamil Cinema', _tamil, onLoadMore: _loadMoreTamil),
                              _buildMovieRow('Popular Movies', _popular, onLoadMore: _loadMorePopular),
                              
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
