import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/movie_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await ApiClient.init();
  runApp(const EzMVMobileApp());
}

class EzMVMobileApp extends StatelessWidget {
  const EzMVMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzMV',
      theme: MobileTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const MobileRootScreen(),
    );
  }
}

class MobileRootScreen extends StatefulWidget {
  const MobileRootScreen({super.key});

  @override
  State<MobileRootScreen> createState() => _MobileRootScreenState();
}

class _MobileRootScreenState extends State<MobileRootScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.video_library_outlined),
            activeIcon: Icon(Icons.video_library_rounded),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Movie> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final list = await LocalStorage.getHistory();
    if (mounted) {
      setState(() {
        _history = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch History & Library'),
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
                  _loadHistory();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: MobileTheme.accent))
          : (_history.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 54, color: Colors.white30),
                      SizedBox(height: 12),
                      Text('No history yet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Movies and TV shows you stream will appear here.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: MobileTheme.accent,
                  backgroundColor: MobileTheme.surfaceElevated,
                  onRefresh: _loadHistory,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2 / 3.7,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final movie = _history[index];
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
