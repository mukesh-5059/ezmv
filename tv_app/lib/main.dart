import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'screens/actor_screen.dart';
import 'screens/details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'theme.dart';
import 'utils/tv_memory.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/tv_shortcuts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initTvMemory();
  MediaKit.ensureInitialized();
  final savedUrl = await StorageService.instance.getApiBaseUrl();
  if (savedUrl != null && savedUrl.isNotEmpty) {
    ApiClient.instance = ApiClient(baseUrl: savedUrl);
  }
  runApp(const EzMVApp());
}

class EzMVApp extends StatelessWidget {
  const EzMVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return TvShortcuts(
      child: MaterialApp(
        title: 'EzMV',
        theme: TVTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/details':
              final args = settings.arguments;
              if (args is MovieSummary) {
                return MaterialPageRoute(
                  builder: (_) => DetailsScreen(
                    imdbId: args.imdbId,
                    mediaType: args.mediaType,
                    tmdbId: args.tmdbId,
                    initialMovie: args,
                  ),
                );
              } else if (args is Map<String, dynamic>) {
                return MaterialPageRoute(
                  builder: (_) => DetailsScreen(
                    imdbId: args['imdbId'] as String? ?? '',
                    mediaType: args['mediaType'] as String? ?? 'movie',
                    tmdbId: args['tmdbId'] as int?,
                  ),
                );
              }
              break;
            case '/actor':
              final args = settings.arguments;
              if (args is ActorSummary) {
                return MaterialPageRoute(
                  builder: (_) => ActorScreen(
                    tmdbId: args.tmdbId,
                    actorName: args.name,
                    profilePath: args.profilePath,
                  ),
                );
              } else if (args is Map<String, dynamic>) {
                return MaterialPageRoute(
                  builder: (_) => ActorScreen(
                    tmdbId: (args['tmdbId'] as num?)?.toInt() ?? 0,
                    actorName: args['actorName'] as String? ?? 'Actor',
                    profilePath: args['profilePath'] as String?,
                  ),
                );
              }
              break;
            case '/player':
              final args = settings.arguments;
              if (args is Map<String, dynamic>) {
                return MaterialPageRoute(
                  builder: (_) => PlayerScreen.fromMap(args),
                );
              }
              break;
            case '/search':
              return MaterialPageRoute(
                builder: (_) => const SearchScreen(),
              );
            case '/settings':
              return MaterialPageRoute(
                builder: (ctx) => Scaffold(
                  backgroundColor: TVTheme.background,
                  body: Center(
                    child: SettingsDialog(
                      onSaved: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              );
          }
          return null;
        },
      ),
    );
  }
}
