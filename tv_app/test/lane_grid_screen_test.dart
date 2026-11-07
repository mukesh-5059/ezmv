import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_core/shared_core.dart';
import 'package:tv_app/screens/lane_grid_screen.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';
import 'package:tv_app/widgets/tv_pill_chip.dart';

class MockApiClient extends Fake implements ApiClient {
  int getLaneCallCount = 0;
  String? lastDashboardId;
  String? lastLaneId;
  int? lastPage;
  String? lastType;
  String? lastGenre;
  int? lastYear;
  double? lastMinRating;
  String? lastSortBy;

  List<MovieSummary> mockItems = [];
  bool mockHasMore = false;
  int mockPage = 1;

  @override
  Future<DashboardLane> getLane(
    String dashboardId,
    String laneId, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
    String? sortBy,
    bool refresh = false,
  }) async {
    getLaneCallCount++;
    lastDashboardId = dashboardId;
    lastLaneId = laneId;
    lastPage = page;
    lastType = type;
    lastGenre = genre;
    lastYear = year;
    lastMinRating = minRating;
    lastSortBy = sortBy;

    return DashboardLane(
      id: laneId,
      title: 'Mock Lane',
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

  late MockApiClient mockApi;

  setUp(() {
    mockApi = MockApiClient();
  });

  Widget buildTestApp({
    String dashboardId = 'tamil',
    String laneId = 'ta_trending',
    String laneTitle = 'Tamil Trending',
    void Function(MovieSummary)? onMovieSelected,
  }) {
    return MaterialApp(
      theme: TVTheme.darkTheme,
      home: LaneGridScreen(
        dashboardId: dashboardId,
        laneId: laneId,
        laneTitle: laneTitle,
        apiClient: mockApi,
        onMovieSelected: onMovieSelected,
      ),
    );
  }

  void configureTvResolution(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('LaneGridScreen Header & Layout', () {
    testWidgets('Renders laneTitle, Back button, Clear Filters button, and 5 Filter Pills',
        (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp(laneTitle: 'Action Blockbusters'));
      await tester.pumpAndSettle();

      expect(find.text('Action Blockbusters'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Genre'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Rating'), findsOneWidget);
      expect(find.text('Sort'), findsOneWidget);

      expect(find.byType(TvPillChip), findsNWidgets(5));
      expect(find.byType(TvFocusCard), findsNWidgets(5));
      expect(find.text('End of Catalog'), findsOneWidget);
    });

    testWidgets('Preserves PageStorageKey on GridView', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(10);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp(dashboardId: 'english', laneId: 'en_action'));
      await tester.pumpAndSettle();

      final gridFinder = find.byKey(const PageStorageKey('lane_grid_english_en_action'));
      expect(gridFinder, findsOneWidget);

      final grid = tester.widget<GridView>(gridFinder);
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 5);
      expect(delegate.crossAxisSpacing, 16);
      expect(delegate.mainAxisSpacing, 16);
      expect(delegate.childAspectRatio, 150 / 225);
    });
  });

  group('Right-Anchored Filter Strip & Selection Flow', () {
    testWidgets('Opening filter strip displays dimension options with checkmark on current selection',
        (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);
      mockApi.mockHasMore = false;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open Genre filter strip by tapping Genre pill
      final genrePill = find.text('Genre');
      await tester.tap(genrePill);
      await tester.pumpAndSettle();

      // Right strip should be visible with title 'Genre'
      expect(find.text('‹ Back'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Comedy'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);

      // 'All' option inside strip has checkmark
      final allOption = find.byKey(const ValueKey('filter_option_genre_All'));
      expect(allOption, findsOneWidget);
      expect(
        find.descendant(of: allOption, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('Selecting an option updates filter, refetches page 1, and dismisses strip',
        (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(10);
      mockApi.mockHasMore = true;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(mockApi.getLaneCallCount, 1);
      expect(mockApi.lastGenre, isNull);

      // Open Genre filter strip
      await tester.tap(find.text('Genre'));
      await tester.pumpAndSettle();

      // Select 'Comedy' option
      final comedyOption = find.text('Comedy');
      expect(comedyOption, findsOneWidget);
      await tester.tap(comedyOption);
      await tester.pumpAndSettle();

      // Strip dismissed
      expect(find.text('‹ Back'), findsNothing);

      // Pill label updated
      expect(find.text('Genre: Comedy'), findsOneWidget);

      // Refetched from page 1 with genre=comedy
      expect(mockApi.getLaneCallCount, 2);
      expect(mockApi.lastPage, 1);
      expect(mockApi.lastGenre, 'comedy');
    });

    testWidgets('Dismissing filter strip via Left arrow or Back key preserves current filter',
        (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open Type filter strip
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      expect(find.text('Media Type'), findsOneWidget);

      // Send D-pad Left key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      // Strip closed, filter untouched
      expect(find.text('Media Type'), findsNothing);
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets('Clear Filters button resets all filters to default and refetches page 1',
        (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Set Type to Movies
      await tester.tap(find.text('Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      expect(find.text('Type: Movies'), findsOneWidget);
      expect(mockApi.lastType, 'movie');

      // Click Clear Filters
      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Genre'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Rating'), findsOneWidget);
      expect(find.text('Sort'), findsOneWidget);
      expect(mockApi.lastType, isNull);
    });
  });

  group('Lookahead Prefetch & Pagination', () {
    testWidgets('Prefetches next page when focused index exceeds items.length - 15',
        (tester) async {
      configureTvResolution(tester);
      // 30 items loaded, hasMore = true
      mockApi.mockItems = generateMockMovies(30);
      mockApi.mockHasMore = true;

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      expect(mockApi.getLaneCallCount, 1);
      expect(mockApi.lastPage, 1);

      // Drag grid up to reveal card 10 (< 30 - 15 = 15)
      await tester.drag(find.byType(GridView), const Offset(0, -300));
      await tester.pumpAndSettle();

      final card10 = find.byKey(const ValueKey('movie_tt00010_10'));
      expect(card10, findsOneWidget);

      final card10Gesture = find.descendant(of: card10, matching: find.byType(GestureDetector));
      Focus.of(tester.element(card10Gesture)).requestFocus();
      await tester.pumpAndSettle();
      expect(mockApi.getLaneCallCount, 1);

      // Drag further down to reveal card 16 (>= 15), focusing it MUST trigger prefetch for page 2!
      await tester.drag(find.byType(GridView), const Offset(0, -1200));
      await tester.pumpAndSettle();

      final card16 = find.byKey(const ValueKey('movie_tt00016_16'));
      expect(card16, findsOneWidget);

      final card16Gesture = find.descendant(of: card16, matching: find.byType(GestureDetector));
      Focus.of(tester.element(card16Gesture)).requestFocus();
      await tester.pumpAndSettle();

      expect(mockApi.getLaneCallCount, 2);
      expect(mockApi.lastPage, 2);
    });
  });

  group('Remote Back Key Hierarchy', () {
    testWidgets('Priority 1: Back closes filter strip if open', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(5);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Open Rating filter strip
      await tester.tap(find.text('Rating'));
      await tester.pumpAndSettle();
      expect(find.text('Minimum Rating'), findsOneWidget);

      // Press Back (Escape key)
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Strip dismissed
      expect(find.text('Minimum Rating'), findsNothing);
    });

    testWidgets('Priority 2: Back smooth-scrolls up to Row 0 when scrolled down', (tester) async {
      configureTvResolution(tester);
      mockApi.mockItems = generateMockMovies(30);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Scroll down
      await tester.drag(find.byType(GridView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.pixels, greaterThan(20));

      // Press Back
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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
          home: const Scaffold(body: Text('Home Screen')),
        ),
      );

      // Push LaneGridScreen onto navigator
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => LaneGridScreen(
            dashboardId: 'tamil',
            laneId: 'ta_trending',
            laneTitle: 'Trending',
            apiClient: mockApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);

      // Press Back at row 0
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsNothing);
      expect(find.text('Home Screen'), findsOneWidget);
    });
  });
}
