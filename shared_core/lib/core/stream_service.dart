import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class StreamService {
  static Future<Map<String, dynamic>> getStreamLinksWithProgress(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    bool bypassCache = false,
    void Function(String message)? onProgress,
  }) async {
    final client = http.Client();
    var queryParams = 'tmdb_id=$tmdbId&media_type=$mediaType&bypass_cache=$bypassCache';
    if (season != null) queryParams += '&season=$season';
    if (episode != null) queryParams += '&episode=$episode';

    final url = Uri.parse('${ApiConfig.baseUrl}/streams/?$queryParams');
    try {
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      final response = await client.send(request).timeout(const Duration(seconds: 45));

      Map<String, dynamic> finalResult = {};
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty) continue;
          try {
            final data = json.decode(jsonStr);
            if (data is Map<String, dynamic>) {
              final step = data['step'];
              final msg = data['message'];
              if (msg != null && onProgress != null) {
                onProgress(msg.toString());
              }
              if (step == 'done' && data['result'] != null) {
                finalResult = Map<String, dynamic>.from(data['result']);
              }
            }
          } catch (_) {}
        }
      }
      client.close();
      return finalResult;
    } catch (e) {
      client.close();
      print('Get streams SSE failed: $e');
      return {};
    }
  }
}
