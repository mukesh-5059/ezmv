import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart';
import '../theme.dart';
import 'list_movies_screen.dart';

class StarredListsScreen extends StatefulWidget {
  const StarredListsScreen({super.key});

  @override
  State<StarredListsScreen> createState() => _StarredListsScreenState();
}

class _StarredListsScreenState extends State<StarredListsScreen> {
  List<TraktList> _starredLists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStarredLists();
  }

  Future<void> _loadStarredLists() async {
    setState(() => _isLoading = true);
    final lists = await LocalStorage.getStarredLists();
    if (mounted) {
      setState(() {
        _starredLists = lists;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Starred Lists${_starredLists.isNotEmpty ? ' (${_starredLists.length})' : ''}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
          : (_starredLists.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_outline_rounded, size: 54, color: Colors.white30),
                      SizedBox(height: 12),
                      Text('No starred lists yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Star curated collections from search to easily access them here.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  onRefresh: _loadStarredLists,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    itemCount: _starredLists.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final list = _starredLists[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: MobileTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ListMoviesScreen(list: list),
                                ),
                              ).then((_) => _loadStarredLists());
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.star_rounded,
                                          color: Colors.amberAccent,
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
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              children: [
                                                if (list.userName.isNotEmpty) ...[
                                                  Text(
                                                    'by @${list.userName}',
                                                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                if (list.likes > 0)
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.favorite, size: 10, color: MobileTheme.accent),
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
                                      const SizedBox(width: 8),
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
                    },
                  ),
                )),
    );
  }
}
