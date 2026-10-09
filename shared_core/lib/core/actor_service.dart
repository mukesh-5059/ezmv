import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/actor.model.dart';
import '../models/movie.model.dart';
import 'api_config.dart';
import 'cache_manager.dart';
import 'tmdb_network_client.dart';

class ActorService {
  static Future<List<Actor>> getCuratedActors({String language = 'ta'}) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'curated_actors:$language';
      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((e) => Actor.fromJson(Map<String, dynamic>.from(e))).toList();
      }

      try {
        final url = Uri.parse('${ApiConfig.cdnBaseUrl}/actors.json');
        final response = await http.get(url).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          final actors = data.map((item) => Actor.fromJson(item)).toList();
          if (actors.isNotEmpty) {
            await CacheManager.set(cacheKey, actors.map((a) => a.toJson()).toList(), CacheManager.detailsTtl);
          }
          return actors;
        }
      } catch (e) {
        print('Get curated actors from CDN failed: $e');
      }
      return [];
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/actors/curated?language=$language');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((item) => Actor.fromJson(item)).toList();
      }
    } catch (e) {
      print('Get curated actors failed: $e');
    }
    return [];
  }

  static Future<ActorFilmography?> getActorFilmography(int personId) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'person_details:$personId';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return ActorFilmography.fromJson(cached);
      }

      if (ApiConfig.hasTmdbKey) {
        try {
          final response = await TmdbNetworkClient.tmdbGet('/person/$personId', {
            'append_to_response': 'combined_credits',
          });
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final credits = data['combined_credits'] ?? {};
            final castList = (credits['cast'] as List? ?? []);

            final seenIds = <String>{};
            final validItems = <Map<String, dynamic>>[];
            final todayStr = DateTime.now().toIso8601String().substring(0, 10);

            for (final raw in castList) {
              if (raw is! Map) continue;
              final item = Map<String, dynamic>.from(raw);
              final mId = item['id'];
              final mediaType = item['media_type'] ?? 'movie';
              final key = '$mId:$mediaType';
              if (mId == null || seenIds.contains(key)) continue;
              seenIds.add(key);

              final posterPath = item['poster_path'];
              if (posterPath == null || (posterPath is String && posterPath.isEmpty)) {
                continue;
              }
              validItems.add(item);
            }

            double getPopularityScore(Map<String, dynamic> x) {
              final pop = (x['popularity'] as num?)?.toDouble() ?? 0.0;
              final votes = (x['vote_count'] as num?)?.toInt() ?? 0;
              final avg = (x['vote_average'] as num?)?.toDouble() ?? 0.0;
              final order = (x['order'] as num?)?.toInt() ?? 10;
              final billingMultiplier = order < 4 ? 1.3 : 1.0;
              return ((pop * 2.5) + (votes * (avg / 5.0))) * billingMultiplier;
            }

            final popularSorted = List<Map<String, dynamic>>.from(validItems)
              ..sort((a, b) => getPopularityScore(b).compareTo(getPopularityScore(a)));

            String getDate(Map<String, dynamic> x) {
              return (x['release_date'] ?? x['first_air_date'] ?? '').toString();
            }

            final recentSorted = validItems
                .where((x) {
                  final d = getDate(x);
                  return d.isNotEmpty && d.compareTo(todayStr) <= 0;
                })
                .toList()
              ..sort((a, b) => getDate(b).compareTo(getDate(a)));

            final filmography = ActorFilmography(
              id: data['id'] ?? personId,
              name: data['name'] ?? '',
              biography: data['biography'] ?? '',
              profilePath: data['profile_path'],
              knownForDepartment: data['known_for_department'] ?? 'Acting',
              birthday: data['birthday'],
              placeOfBirth: data['place_of_birth'],
              popular: popularSorted.take(30).map((e) => Movie.fromJson(e)).toList(),
              recent: recentSorted.take(30).map((e) => Movie.fromJson(e)).toList(),
            );
            await CacheManager.set(cacheKey, filmography.toJson(), CacheManager.detailsTtl);
            return filmography;
          }
        } catch (e) {
          print('Direct TMDB getActorFilmography failed: $e');
        }
      }
      return null;
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/person/$personId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ActorFilmography.fromJson(data);
      }
    } catch (e) {
      print('Get actor filmography failed: $e');
    }
    return null;
  }
}
