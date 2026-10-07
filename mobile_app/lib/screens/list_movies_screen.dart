import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import '../widgets/movie_card.dart';

class ListMoviesScreen extends StatefulWidget {
  final TraktList list;

  const ListMoviesScreen({
    super.key,
    required this.list,
  });

  @override
  State<ListMoviesScreen> createState() => _ListMoviesScreenState();
}

class _ListMoviesScreenState extends State<ListMoviesScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Movie> _movies = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  bool _isDescExpanded = false;
  bool _isStarred = false;
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _checkStarred();
    _loadMovies();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final showBtn = _scrollController.offset > 400;
      if (showBtn != _showBackToTop) {
        setState(() => _showBackToTop = showBtn);
      }

      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        if (!_isLoading && !_isLoadingMore && _hasMore) {
          _loadMore();
        }
      }
    }
  }

  Future<void> _checkStarred() async {
    final starred = await LocalStorage.isListStarred(widget.list.id);
    if (mounted) {
      setState(() => _isStarred = starred);
    }
  }

  Future<void> _toggleStar() async {
    final starred = await LocalStorage.toggleStarredList(widget.list);
    if (mounted) {
      setState(() => _isStarred = starred);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                starred ? Icons.star_rounded : Icons.star_border_rounded,
                color: starred ? Colors.amberAccent : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                starred ? 'Added to Starred Lists' : 'Removed from Starred Lists',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: MobileTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
      _page = 1;
    });

    final items = await ApiClient.getListItems(listId: widget.list.id, page: 1, limit: 50);

    if (mounted) {
      setState(() {
        _movies = items;
        _isLoading = false;
        _hasMore = items.length >= 50;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    final nextPage = _page + 1;
    final items = await ApiClient.getListItems(listId: widget.list.id, page: nextPage, limit: 50);

    if (mounted) {
      setState(() {
        _page = nextPage;
        _movies.addAll(items);
        _isLoadingMore = false;
        _hasMore = items.length >= 50;
      });
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
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
        title: Text(widget.list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(
              _isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _isStarred ? Colors.amberAccent : Colors.white70,
            ),
            tooltip: _isStarred ? 'Starred' : 'Star List',
            onPressed: _toggleStar,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
          : RefreshIndicator(
              color: MobileTheme.accent,
              backgroundColor: MobileTheme.surfaceElevated,
              onRefresh: _loadMovies,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Spacer(),
                              InkWell(
                                onTap: _toggleStar,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                  decoration: BoxDecoration(
                                    color: _isStarred ? Colors.amber.withValues(alpha: 0.15) : Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isStarred ? Colors.amberAccent.withValues(alpha: 0.5) : Colors.white12,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                                        size: 15,
                                        color: _isStarred ? Colors.amberAccent : Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isStarred ? 'Starred' : 'Star',
                                        style: TextStyle(
                                          color: _isStarred ? Colors.amberAccent : Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                                decoration: BoxDecoration(
                                  color: MobileTheme.accent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: MobileTheme.accent.withValues(alpha: 0.6),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  '${widget.list.itemCount} items',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.list.name,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (widget.list.userName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text('Curated by @${widget.list.userName}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                          if (widget.list.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => setState(() => _isDescExpanded = !_isDescExpanded),
                              borderRadius: BorderRadius.circular(4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.list.description.trim(),
                                    maxLines: _isDescExpanded ? null : 2,
                                    overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.3),
                                  ),
                                  if (widget.list.description.trim().length > 80 || widget.list.description.contains('\n'))
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
                  if (_movies.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text('No titles found in this list.', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
                            final movie = _movies[index];
                            return MovieCard(
                              movie: movie,
                              width: double.infinity,
                              height: 160,
                            );
                          },
                          childCount: _movies.length,
                        ),
                      ),
                    ),
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: MobileTheme.accent)),
                      ),
                    ),
                  if (!_hasMore && _movies.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
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
                                      const Icon(Icons.check_circle_outline_rounded, color: Colors.white54, size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'End of ${widget.list.name} (${_movies.length} loaded)',
                                        style: const TextStyle(
                                          color: Colors.white60,
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
                                  side: const BorderSide(color: Colors.white12),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_upward_rounded, size: 15),
                              label: const Text('Back to Top', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _scrollToTop,
                            ),
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
