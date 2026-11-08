import 'package:flutter_test/flutter_test.dart';
import 'package:shared_core/shared_core.dart';

void main() {
  group('Genre Model', () {
    test('fromJson and toJson', () {
      final json = {'slug': 'action', 'name': 'Action'};
      final genre = Genre.fromJson(json);
      expect(genre.slug, 'action');
      expect(genre.name, 'Action');
      expect(genre.toJson(), json);
    });
  });

  group('CastMember Model', () {
    test('fromJson, toJson, and profileUrl', () {
      final json = {
        'tmdb_id': 239019,
        'name': 'Emilia Clarke',
        'character': 'Daenerys Targaryen',
        'profile_path': '/92B9m.jpg',
        'order': 0,
      };
      final cast = CastMember.fromJson(json);
      expect(cast.tmdbId, 239019);
      expect(cast.name, 'Emilia Clarke');
      expect(cast.character, 'Daenerys Targaryen');
      expect(cast.profileUrl, 'https://image.tmdb.org/t/p/w185/92B9m.jpg');
      expect(cast.toJson(), json);
    });

    test('profileUrl handles full URL', () {
      final json = {
        'tmdb_id': 1,
        'name': 'Actor',
        'character': 'Char',
        'profile_path': 'https://custom.com/pic.jpg',
      };
      final cast = CastMember.fromJson(json);
      expect(cast.profileUrl, 'https://custom.com/pic.jpg');
    });
  });

  group('MovieSummary Model', () {
    test('fromJson and getters', () {
      final json = {
        'imdb_id': 'tt0111161',
        'tmdb_id': 278,
        'title': 'The Shawshank Redemption',
        'overview': 'Imprisoned in the 1940s...',
        'release_date': '1994-09-23',
        'poster_path': '/9cqNxx0GxF0bflZmeSMuL5tnGzr.jpg',
        'backdrop_path': '/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg',
        'rating_score': 9.3,
        'vote_count': 2800000,
        'media_type': 'movie',
        'genres': [
          {'slug': 'drama', 'name': 'Drama'},
          {'slug': 'crime', 'name': 'Crime'},
        ],
      };
      final movie = MovieSummary.fromJson(json);
      expect(movie.imdbId, 'tt0111161');
      expect(movie.tmdbId, 278);
      expect(movie.year, '1994');
      expect(movie.isMovie, true);
      expect(movie.isTv, false);
      expect(movie.formattedRating, '9.3');
      expect(movie.formattedVoteCount, '2.8M');
      expect(movie.posterUrl, 'https://image.tmdb.org/t/p/w500/9cqNxx0GxF0bflZmeSMuL5tnGzr.jpg');
      expect(movie.backdropUrl, 'https://image.tmdb.org/t/p/w1280/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg');
      expect(movie.genres.length, 2);
    });

    test('voteCount formatting edge cases', () {
      const summary1 = MovieSummary(
        imdbId: 'tt1',
        title: 'T1',
        overview: '',
        releaseDate: '2020-01-01',
        posterPath: '',
        backdropPath: '',
        ratingScore: 8.0,
        voteCount: 1500,
        mediaType: 'movie',
        genres: [],
      );
      expect(summary1.formattedVoteCount, '1.5K');

      const summary2 = MovieSummary(
        imdbId: 'tt2',
        title: 'T2',
        overview: '',
        releaseDate: '2020-01-01',
        posterPath: '',
        backdropPath: '',
        ratingScore: 8.0,
        voteCount: 450,
        mediaType: 'movie',
        genres: [],
      );
      expect(summary2.formattedVoteCount, '450');
    });
  });

  group('MovieDetails Model', () {
    test('fromJson and formattedRuntime', () {
      final json = {
        'imdb_id': 'tt0944947',
        'tmdb_id': 1399,
        'title': 'Game of Thrones',
        'overview': 'Seven noble families...',
        'release_date': '2011-04-17',
        'poster_path': '',
        'backdrop_path': '',
        'rating_score': 9.2,
        'vote_count': 2200000,
        'media_type': 'tv',
        'genres': [
          {'slug': 'drama', 'name': 'Drama'},
        ],
        'runtime': 65,
        'cast': [
          {
            'tmdb_id': 239019,
            'name': 'Emilia Clarke',
            'character': 'Daenerys Targaryen',
            'order': 0,
          }
        ],
        'seasons': [
          {
            'season_number': 1,
            'name': 'Season 1',
            'episode_count': 10,
          }
        ],
        'status': 'Ended',
        'is_ongoing': false,
        'original_language': 'en',
      };
      final details = MovieDetails.fromJson(json);
      expect(details.formattedRuntime, '1h 5m');
      expect(details.cast.length, 1);
      expect(details.seasons.length, 1);
      expect(details.status, 'Ended');
      expect(details.isOngoing, false);
      expect(details.originalLanguage, 'en');
    });
  });

  group('TvSeason & TvEpisode', () {
    test('TvEpisode fromJson and formattedRuntime', () {
      final json = {
        'episode_number': 1,
        'name': 'Winter Is Coming',
        'overview': 'Overview...',
        'still_path': '/still.jpg',
        'air_date': '2011-04-17',
        'runtime': 62,
        'is_released': true,
      };
      final ep = TvEpisode.fromJson(json);
      expect(ep.episodeNumber, 1);
      expect(ep.name, 'Winter Is Coming');
      expect(ep.stillUrl, 'https://image.tmdb.org/t/p/w500/still.jpg');
      expect(ep.formattedRuntime, '62m');
      expect(ep.isReleased, true);
      expect(ep.formattedAirDate, 'Apr 17, 2011');
      expect(ep.isUpcoming, false);

      final upcomingJson = {
        'episode_number': 2,
        'name': 'The Kingsroad',
        'overview': 'Overview...',
        'air_date': '2099-12-31',
        'is_released': false,
      };
      final upcomingEp = TvEpisode.fromJson(upcomingJson);
      expect(upcomingEp.formattedAirDate, 'Dec 31, 2099');
      expect(upcomingEp.isUpcoming, true);
    });

    test('TvSeason fromJson', () {
      final json = {
        'season_number': 1,
        'name': 'Season 1',
        'episode_count': 1,
        'episodes': [
          {
            'episode_number': 1,
            'name': 'Ep 1',
            'overview': '',
          }
        ],
      };
      final season = TvSeason.fromJson(json);
      expect(season.seasonNumber, 1);
      expect(season.episodes.length, 1);
      expect(season.episodes.first.name, 'Ep 1');
    });
  });

  group('StreamSource & SubtitleTrack', () {
    test('StreamSource fromJson', () {
      final json = {
        'url': 'https://pengu.uk/stream.mp4',
        'quality': '1080p',
        'filename': 'Movie.mp4',
        'size_bytes': 1048576,
        'formatted_size': '1.0 MB',
        'priority': 30,
        'provider': 'penguplay',
        'host': 'pengu.uk',
        'languages': ['English', 'Tamil'],
        'headers': {'User-Agent': 'TestAgent'},
      };
      final stream = StreamSource.fromJson(json);
      expect(stream.url, 'https://pengu.uk/stream.mp4');
      expect(stream.quality, '1080p');
      expect(stream.languages, ['English', 'Tamil']);
      expect(stream.headers?['User-Agent'], 'TestAgent');
    });

    test('SubtitleTrack fromJson and isEnglish', () {
      final json = {
        'name': 'English Sub',
        'language': 'English',
        'url': 'https://opensubtitles.org/sub.vtt',
        'popularity': 100,
      };
      final sub = SubtitleTrack.fromJson(json);
      expect(sub.name, 'English Sub');
      expect(sub.isEnglish, true);
    });
  });

  group('Dashboard & DashboardLane', () {
    test('Dashboard fromJson', () {
      final json = {
        'id': 'tamil',
        'title': 'Tamil Cinema',
        'lanes': [
          {
            'id': 'ta_trending',
            'title': 'Trending Now',
            'items': [],
            'page': 1,
            'total_pages': 3,
            'total_items': 250,
            'has_more': true,
            'next_page': 2,
          }
        ],
      };
      final dashboard = Dashboard.fromJson(json);
      expect(dashboard.id, 'tamil');
      expect(dashboard.lanes.length, 1);
      expect(dashboard.lanes.first.id, 'ta_trending');
      expect(dashboard.lanes.first.hasMore, true);
      expect(dashboard.lanes.first.nextPage, 2);
    });
  });

  group('ActorSummary & ActorProfile', () {
    test('ActorProfile fromJson', () {
      final json = {
        'tmdb_id': 146939,
        'name': 'Kamal Haasan',
        'biography': 'Indian actor...',
        'profile_path': '/pic.jpg',
        'popular': [],
        'recent': [],
      };
      final profile = ActorProfile.fromJson(json);
      expect(profile.tmdbId, 146939);
      expect(profile.name, 'Kamal Haasan');
      expect(profile.profileUrl, 'https://image.tmdb.org/t/p/w500/pic.jpg');
    });
  });

  group('PaginatedResponse', () {
    test('PaginatedResponse fromJson with generic items', () {
      final json = {
        'items': [
          {'id': 10, 'name': 'List 10', 'item_count': 50, 'likes': 25},
        ],
        'page': 1,
        'total_pages': 5,
        'total_items': 50,
        'has_more': true,
        'next_page': 2,
      };
      final resp = PaginatedResponse<TraktListSummary>.fromJson(
        json,
        (item) => TraktListSummary.fromJson(item as Map<String, dynamic>),
      );
      expect(resp.items.length, 1);
      expect(resp.items.first.name, 'List 10');
      expect(resp.page, 1);
      expect(resp.hasMore, true);
      expect(resp.nextPage, 2);
    });
  });

  group('ContinueWatchingEntry', () {
    test('fromJson and progress calculation', () {
      final now = DateTime.now();
      final json = {
        'imdb_id': 'tt0816692',
        'title': 'Interstellar',
        'poster_path': '/interstellar.jpg',
        'backdrop_path': '/backdrop.jpg',
        'media_type': 'movie',
        'position_ms': 50000,
        'duration_ms': 100000,
        'updated_at': now.toIso8601String(),
      };
      final entry = ContinueWatchingEntry.fromJson(json);
      expect(entry.imdbId, 'tt0816692');
      expect(entry.progress, 0.5);
      expect(entry.isCompleted, false);
      expect(entry.isMovie, true);
      expect(entry.isTv, false);
    });

    test('isCompleted when progress >= 92%', () {
      final entry = ContinueWatchingEntry(
        imdbId: 'tt1',
        title: 'Title',
        mediaType: 'movie',
        positionMs: 95000,
        durationMs: 100000,
        updatedAt: DateTime.now(),
      );
      expect(entry.progress, 0.95);
      expect(entry.isCompleted, true);
    });
  });
}
