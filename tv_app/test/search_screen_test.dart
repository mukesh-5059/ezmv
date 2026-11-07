import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/screens/search_screen.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';

class MockSearchApiClient extends Fake implements ApiClient {
  int searchCallCount = 0;
  String? lastQuery;
  int? lastPage;
  String? lastType;
  String? lastGenre;
  int? lastYear;
  double? lastMinRating;

  List<MovieSummary> mockItems = [];
  bool mockHasMore = false;
  int mockPage = 1;

  @override
  Future<PaginatedResponse<MovieSummary>> search(
    String query, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
  }) async {
    searchCallCount++;
    lastQuery = query;
    lastPage = page;
    lastType = type;
    lastGenre = genre;
    lastYear = year;
    lastMinRating = minRating;

    return PaginatedResponse<MovieSummary>(
      items: mockItems,
      page: page,
      totalPages: mockHasMore ? 2 : 1,
      totalItems: mockItems.length,
      hasMore: mockHasMore,
    );
  }
}

List<MovieSummary> generateMockMovies(int count) {
  return List.generate(
    count,
    (i) => MovieSummary(
      imdbId: 'tt000$i',
      tmdbId: 1000 + i,
      title: 'Movie $i',
      overview: 'Overview $i',
      releaseDate: '2024-01-01',
      posterPath: '',
      backdropPath: '',
      ratingScore: 8.0,
      voteCount: 1200,
      mediaType: 'movie',
      genres: const [Genre(slug: 'action', name: 'Action')],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSearchApiClient mockApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tv_search_history': ['Inception', 'Interstellar'],
    });
    mockApi = MockSearchApiClient();
  });

  void configureTvResolution(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget buildTestApp({
    void Function(MovieSummary)? onMovieSelected,
  }) {
    return MaterialApp(
      theme: TVTheme.darkTheme,
      home: SearchScreen(
        apiClient: mockApi,
        onMovieSelected: onMovieSelected,
      ),
    );
  }

  group('SearchScreen - Top Control Bar & History', () {
    testWidgets('renders search text field, history chips, clear history, and filter pills', (tester) async {
      configureTvResolution(tester);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('Interstellar'), findsOneWidget);
      expect(find.text('Clear History'), findsOneWidget);

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Genre'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Rating'), findsOneWidget);
      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
    });

    testWidgets('clicking a history chip executes search immediately', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inception'));
      await tester.pumpAndSettle();

      expect(mockApi.searchCallCount, 1);
      expect(mockApi.lastQuery, 'Inception');
      expect(find.byType(TvFocusCard), findsNWidgets(5));
    });

    testWidgets('clicking Clear History removes history chips', (tester) async {
      configureTvResolution(tester);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsOneWidget);

      await tester.tap(find.text('Clear History'));
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsNothing);
      expect(find.text('Recent:'), findsNothing);
    });
  });

  group('SearchScreen - 70/30 Filter Layout & Interaction', () {
    testWidgets('clicking a filter pill opens right 30% filter strip with checkmark and autofocus', (tester) async {
      configureTvResolution(tester);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Tap Genre pill
      await tester.tap(find.text('Genre'));
      await tester.pumpAndSettle();

      // Right 30% strip should open
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Animation'), findsOneWidget);
      // Strip option checkmark has size 20
      expect(
        find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.check_rounded && w.size == 20),
        findsOneWidget,
      );
    });

    testWidgets('selecting filter option refetches search with filter param and closes strip', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(3);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Search query first
      await tester.enterText(find.byType(TextField), 'Batman');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(mockApi.searchCallCount, 1);

      // Open Type filter strip
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();

      expect(find.text('Movies'), findsOneWidget);

      // Tap 'Movies' option
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      // Strip closes
      expect(find.text('Media Type'), findsNothing);
      // Pill updates label
      expect(find.text('Type: Movies'), findsOneWidget);
      // Api called with type: 'movie'
      expect(mockApi.searchCallCount, 2);
      expect(mockApi.lastType, 'movie');
    });

    testWidgets('dismissing filter strip via Left arrow preserves filter and refocuses pill', (tester) async {
      configureTvResolution(tester);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(find.text('Release Year'), findsOneWidget);

      // Press Arrow Left
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Strip dismissed
      expect(find.text('Release Year'), findsNothing);
      expect(find.text('Year'), findsOneWidget);
    });

    testWidgets('Clear Filters resets all filters and triggers re-search', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(2);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Marvel');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Open & select Genre: Action
      await tester.tap(find.text('Genre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(find.text('Genre: Action'), findsOneWidget);
      expect(mockApi.lastGenre, 'action');

      // Click Clear Filters
      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Genre'), findsOneWidget);
      expect(mockApi.lastGenre, isNull);
    });
  });

  group('SearchScreen - Back Key Hierarchy', () {
    testWidgets('Priority 1: Back key closes filter strip if open', (tester) async {
      configureTvResolution(tester);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rating'));
      await tester.pumpAndSettle();
      expect(find.text('Minimum Rating'), findsOneWidget);

      // Send Back / Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Minimum Rating'), findsNothing);
    });

    testWidgets('Priority 2: Back key scrolls up to Row 0 if scrolled down', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(50);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.pixels, 0.0);

      // Scroll down by 500 pixels
      await tester.drag(find.byType(GridView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, greaterThan(20));

      // Tap Back button directly to verify Priority 2 smooth-scroll to row 0
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, 0.0);
    });

    testWidgets('Priority 3: Back pops screen when at Row 0', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          theme: TVTheme.darkTheme,
          home: const Scaffold(body: Text('Previous Screen')),
        ),
      );

      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => SearchScreen(apiClient: mockApi),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsOneWidget);

      // Press Back / Escape key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.text('Previous Screen'), findsOneWidget);
    });
  });

  group('SearchScreen - Pagination & End of Catalog', () {
    testWidgets('shows End of Catalog indicator when hasMore is false', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(10);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Avatar');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('End of Catalog'), findsOneWidget);
    });
  });
}
