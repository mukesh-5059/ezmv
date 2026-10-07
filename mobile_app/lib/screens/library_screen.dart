import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';
import 'watchlist_screen.dart';
import 'starred_lists_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Movie> _history = [];
  int _watchlistCount = 0;
  int _starredListsCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final historyList = await LocalStorage.getHistory();
    final watchlist = await LocalStorage.getWatchlist();
    final starredLists = await LocalStorage.getStarredLists();

    if (mounted) {
      setState(() {
        _history = historyList;
        _watchlistCount = watchlist.length;
        _starredListsCount = starredLists.length;
        _isLoading = false;
      });
    }
  }

  Widget _buildPrimaryRedCard({
    required String title,
    required String subtitle,
    required int count,
    required String countSuffix,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  MobileTheme.accent.withValues(alpha: 0.28),
                  MobileTheme.surfaceElevated,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MobileTheme.accent.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MobileTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24, width: 0.6),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Library',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
              tooltip: 'Clear History',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: MobileTheme.surfaceElevated,
                    title: const Text('Clear Watch History?', style: TextStyle(color: Colors.white)),
                    content: const Text('This will remove all titles from your local history list.', style: TextStyle(color: Colors.white70)),
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
                  await LocalStorage.clearHistory();
                  _loadData();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
          : RefreshIndicator(
              color: MobileTheme.accent,
              backgroundColor: MobileTheme.surfaceElevated,
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  // Top Red Cards
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      child: Row(
                        children: [
                          _buildPrimaryRedCard(
                            title: 'Watchlist',
                            subtitle: 'Saved Titles',
                            count: _watchlistCount,
                            countSuffix: 'items',
                            icon: Icons.bookmark_rounded,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const WatchlistScreen(),
                                ),
                              ).then((_) => _loadData());
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildPrimaryRedCard(
                            title: 'Starred Lists',
                            subtitle: 'Curated Collections',
                            count: _starredListsCount,
                            countSuffix: 'lists',
                            icon: Icons.star_rounded,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const StarredListsScreen(),
                                ),
                              ).then((_) => _loadData());
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Section Header: Watch History
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'CONTINUE WATCHING & HISTORY${_history.isNotEmpty ? ' (${_history.length})' : ''}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),

                  if (_history.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.white30),
                            SizedBox(height: 12),
                            Text('No history yet', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                            SizedBox(height: 4),
                            Text('Movies and TV shows you stream will appear here.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  else
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
                          (context, index) {
                            final movie = _history[index];
                            return MovieCard(
                              movie: movie,
                              width: double.infinity,
                              height: 160,
                            );
                          },
                          childCount: _history.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }
}
