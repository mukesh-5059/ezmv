import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_core/shared_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageService - Continue Watching', () {
    test('save, get, and update continue watching', () async {
      final storage = StorageService();

      final entry1 = ContinueWatchingEntry(
        imdbId: 'tt0111161',
        title: 'The Shawshank Redemption',
        mediaType: 'movie',
        positionMs: 10000,
        durationMs: 60000,
        updatedAt: DateTime(2024, 1, 1, 10, 0),
      );

      final entry2 = ContinueWatchingEntry(
        imdbId: 'tt0816692',
        title: 'Interstellar',
        mediaType: 'movie',
        positionMs: 20000,
        durationMs: 80000,
        updatedAt: DateTime(2024, 1, 1, 11, 0),
      );

      await storage.saveContinueWatching(entry1);
      await storage.saveContinueWatching(entry2);

      var list = await storage.getContinueWatching();
      expect(list.length, 2);
      expect(list.first.imdbId, 'tt0816692'); // Most recently updated first

      // Update entry1 with newer timestamp
      final updatedEntry1 = ContinueWatchingEntry(
        imdbId: 'tt0111161',
        title: 'The Shawshank Redemption',
        mediaType: 'movie',
        positionMs: 30000,
        durationMs: 60000,
        updatedAt: DateTime(2024, 1, 1, 12, 0),
      );

      await storage.saveContinueWatching(updatedEntry1);
      list = await storage.getContinueWatching();
      expect(list.length, 2);
      expect(list.first.imdbId, 'tt0111161');
      expect(list.first.positionMs, 30000);

      // Fetch single
      final fetched = await storage.getContinueWatchingEntry('tt0111161');
      expect(fetched?.title, 'The Shawshank Redemption');

      // Remove
      await storage.removeContinueWatching('tt0111161');
      list = await storage.getContinueWatching();
      expect(list.length, 1);
      expect(list.first.imdbId, 'tt0816692');

      // Clear
      await storage.clearContinueWatching();
      list = await storage.getContinueWatching();
      expect(list.isEmpty, true);
    });
  });

  group('StorageService - Favorite Actors', () {
    test('add, remove, query and toggle favorite actors', () async {
      final storage = StorageService();

      expect(await storage.isActorFavorite(146939), false);

      await storage.addFavoriteActor(146939);
      expect(await storage.isActorFavorite(146939), true);
      expect(await storage.getFavoriteActorIds(), {146939});

      // Toggle off
      final result1 = await storage.toggleFavoriteActor(146939);
      expect(result1, false);
      expect(await storage.isActorFavorite(146939), false);

      // Toggle on
      final result2 = await storage.toggleFavoriteActor(146939);
      expect(result2, true);
      expect(await storage.isActorFavorite(146939), true);

      // Remove
      await storage.removeFavoriteActor(146939);
      expect(await storage.isActorFavorite(146939), false);
    });
  });

  group('StorageService - Watchlist & Starred Lists', () {
    test('watchlist add, query, remove', () async {
      final storage = StorageService();

      const movie = MovieSummary(
        imdbId: 'tt0111161',
        title: 'Shawshank',
        overview: '',
        releaseDate: '1994-09-23',
        posterPath: '',
        backdropPath: '',
        ratingScore: 9.3,
        voteCount: 2800000,
        mediaType: 'movie',
        genres: [],
      );

      expect(await storage.isWatchlisted('tt0111161'), false);
      await storage.addToWatchlist(movie);
      expect(await storage.isWatchlisted('tt0111161'), true);

      final list = await storage.getWatchlist();
      expect(list.length, 1);
      expect(list.first.imdbId, 'tt0111161');

      await storage.removeFromWatchlist('tt0111161');
      expect(await storage.isWatchlisted('tt0111161'), false);
    });

    test('starred lists add, query, remove', () async {
      final storage = StorageService();

      const listSummary = TraktListSummary(
        id: 12345,
        name: 'Top 100',
        itemCount: 100,
        likes: 50,
      );

      expect(await storage.isListStarred(12345), false);
      await storage.addStarredList(listSummary);
      expect(await storage.isListStarred(12345), true);

      final lists = await storage.getStarredLists();
      expect(lists.length, 1);
      expect(lists.first.id, 12345);

      await storage.removeStarredList(12345);
      expect(await storage.isListStarred(12345), false);
    });
  });
}
