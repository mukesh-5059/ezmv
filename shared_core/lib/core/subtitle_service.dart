import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subtitle.model.dart';
import 'api_config.dart';
import 'tmdb_network_client.dart';

class SubtitleService {
  static Future<List<SubtitleTrackInfo>> getSubtitles(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    String? language,
    String? imdbId,
  }) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      try {
        var resolvedImdbId = imdbId;
        if ((resolvedImdbId == null || resolvedImdbId.isEmpty) && ApiConfig.hasTmdbKey) {
          final cleanType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
          final resp = await TmdbNetworkClient.tmdbGet('/$cleanType/$tmdbId/external_ids');
          if (resp != null && resp.statusCode == 200) {
            final data = json.decode(resp.body);
            resolvedImdbId = data['imdb_id']?.toString();
          }
        }

        if (resolvedImdbId != null && resolvedImdbId.isNotEmpty) {
          final cleanType = mediaType.toLowerCase() == 'tv' ? 'series' : 'movie';
          final querySegment = cleanType == 'series'
              ? '$cleanType/$resolvedImdbId:${season ?? 1}:${episode ?? 1}'
              : '$cleanType/$resolvedImdbId';
          final url = Uri.parse('https://opensubtitles-v3.strem.io/subtitles/$querySegment.json');
          final resp = await http.get(url).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            final List subs = data['subtitles'] ?? [];
            return subs.map((s) {
              return SubtitleTrackInfo(
                id: s['id']?.toString(),
                language: s['lang'] ?? s['language'] ?? 'Unknown',
                code: s['lang'] ?? 'und',
                url: s['url'] ?? '',
                format: 'vtt',
                release: null,
              );
            }).toList();
          }
        }
      } catch (e) {
        print('Direct Stremio getSubtitles failed: $e');
      }
      return [];
    }

    var query = 'tmdb_id=$tmdbId&media_type=$mediaType';
    if (season != null) query += '&season=$season';
    if (episode != null) query += '&episode=$episode';
    if (language != null) query += '&language=$language';

    final url = Uri.parse('${ApiConfig.baseUrl}/subtitles/?$query');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final subtitleResponse = SubtitleResponse.fromJson(Map<String, dynamic>.from(data));
        return subtitleResponse.subtitles;
      }
    } catch (e) {
      print('Get subtitles failed: $e');
    }
    return [];
  }
}
