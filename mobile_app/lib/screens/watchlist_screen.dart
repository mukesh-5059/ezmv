import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<Movie> _watchlist = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWatchlist();
  }

  Future<void> _loadWatchlist() async {
    setState(() => _isLoading = true);
    final list = await LocalStorage.getWatchlist();
    if (mounted) {
      setState(() {
        _watchlist = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Watchlist${_watchlist.isNotEmpty ? ' (${_watchlist.length})' : ''}'),
        actions: [
          if (_watchlist.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
              tooltip: 'Clear Watchlist',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: MobileTheme.surfaceElevated,
                    title: const Text('Clear Watchlist?', style: TextStyle(color: Colors.white)),
                    content: const Text('This will remove all saved titles from your watchlist.', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: MobileTheme.accent),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  for (final m in _watchlist) {
                    await LocalStorage.removeFromWatchlist(m.tmdbId);
                  }
                  _loadWatchlist();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
          : (_watchlist.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_outline_rounded, size: 54, color: Colors.white30),
                      SizedBox(height: 12),
                      Text('Your Watchlist is empty', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Bookmark movies and TV shows to watch them later.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  onRefresh: _loadWatchlist,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2 / 3.7,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _watchlist.length,
                    itemBuilder: (context, index) {
                      final movie = _watchlist[index];
                      return MovieCard(
                        movie: movie,
                        width: double.infinity,
                        height: 160,
                      );
                    },
                  ),
                )),
    );
  }
}
