import 'package:flutter/material.dart';
import '../models/movie.model.dart';
import '../core/api_client.dart';
import '../core/local_storage.dart';
import '../theme.dart';
import 'player_screen.dart';

class DetailsScreen extends StatefulWidget {
  final Movie movie;

  const DetailsScreen({Key? key, required this.movie}) : super(key: key);

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  List<Map<String, dynamic>> _streams = [];
  bool _isLoadingStreams = true;

  @override
  void initState() {
    super.initState();
    _fetchStreams();
  }

  Future<void> _fetchStreams() async {
    setState(() => _isLoadingStreams = true);
    final streams = await ApiClient.getStreamLinks(widget.movie.tmdbId);
    setState(() {
      _streams = streams;
      _isLoadingStreams = false;
    });
  }

  void _startPlayback(String streamUrl) async {
    // 1. Add movie to recently viewed history list
    await LocalStorage.addToHistory(widget.movie);
    
    if (!mounted) return;
    
    // 2. Play stream
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: streamUrl,
          movieTitle: widget.movie.title,
          tmdbId: widget.movie.tmdbId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. Full Screen Backdrop Image
          if (widget.movie.backdropUrl.isNotEmpty)
            Positioned.fill(
              child: Image.network(
                widget.movie.backdropUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Vignette
          Positioned.fill(
            child: Container(
              color: TVTheme.background.withOpacity(0.85),
            ),
          ),

          // 2. Details Content
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Poster Card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: size.width * 0.22,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: Image.network(
                          widget.movie.posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: TVTheme.surface),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),

                  // Metadata Description & Stream Selector
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.movie.title,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            Text(
                              widget.movie.releaseDate.split('-')[0],
                              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                            ),
                            Text(
                              'Language: ${widget.movie.originalLanguage.toUpperCase()}',
                              style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14),
                            ),
                            Text(
                              'Rating: ${widget.movie.voteAverage.toStringAsFixed(1)}',
                              style: const TextStyle(color: TVTheme.accent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.movie.overview,
                          style: const TextStyle(color: TVTheme.textSecondary, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 40),

                        // Action Play & Stream Options
                        const Text(
                          'Select Server Source:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingStreams)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: TVTheme.accent, strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('Scraping stream sources...', style: TextStyle(color: TVTheme.textSecondary))
                              ],
                            ),
                          )
                        else if (_streams.isEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No streams found or failed to connect. Verify your backend server is online.',
                                style: TextStyle(color: TVTheme.accent, fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              Focus(
                                child: Builder(
                                  builder: (context) {
                                    final focused = Focus.of(context).hasFocus;
                                    return ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: focused ? Colors.white : TVTheme.surface,
                                        foregroundColor: focused ? Colors.black : Colors.white,
                                      ),
                                      onPressed: _fetchStreams,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry Fetching'),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )
                        else
                          // Render horizontal list of focused stream button options
                          SizedBox(
                            height: 50,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _streams.length,
                              itemBuilder: (context, index) {
                                final stream = _streams[index];
                                final providerName = stream['provider'] ?? 'Source ${index + 1}';
                                final streamUrl = stream['url'] ?? '';

                                return Focus(
                                  child: Builder(
                                    builder: (context) {
                                      final focused = Focus.of(context).hasFocus;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 12.0),
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: focused ? TVTheme.accent : TVTheme.surface,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: focused ? Colors.white : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                          onPressed: () => _startPlayback(streamUrl),
                                          child: Text(providerName),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}
