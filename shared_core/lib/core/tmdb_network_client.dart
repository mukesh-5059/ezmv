import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class TmdbNetworkClient {
  static List<String> _cachedTmdbIps = [];
  static DateTime? _lastDohResolution;

  static Future<List<String>> resolveTmdbDoH(String host) async {
    if (_cachedTmdbIps.isNotEmpty &&
        _lastDohResolution != null &&
        DateTime.now().difference(_lastDohResolution!).inMinutes < 30) {
      return _cachedTmdbIps;
    }

    final dohEndpoints = [
      'https://1.1.1.1/dns-query?name=$host&type=A',
      'https://8.8.8.8/resolve?name=$host&type=A',
    ];

    final client = HttpClient();
    client.badCertificateCallback = (cert, h, port) => true;

    for (final endpoint in dohEndpoints) {
      try {
        final req = await client.getUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 3));
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = json.decode(body);
          if (data['Answer'] != null) {
            final ips = <String>[];
            for (final ans in data['Answer']) {
              if (ans['type'] == 1 && ans['data'] != null) {
                ips.add(ans['data'].toString());
              }
            }
            if (ips.isNotEmpty) {
              _cachedTmdbIps = ips;
              _lastDohResolution = DateTime.now();
              client.close();
              return ips;
            }
          }
        }
      } catch (_) {}
    }
    client.close();
    return [];
  }

  static List<int> decodeChunked(List<int> bytes) {
    final decoded = <int>[];
    int offset = 0;
    while (offset < bytes.length) {
      int lineEnd = -1;
      for (int i = offset; i < bytes.length - 1; i++) {
        if (bytes[i] == 13 && bytes[i + 1] == 10) {
          lineEnd = i;
          break;
        }
      }
      if (lineEnd == -1) break;
      final sizeStr = utf8.decode(bytes.sublist(offset, lineEnd)).trim().split(';').first;
      final chunkSize = int.tryParse(sizeStr, radix: 16) ?? 0;
      if (chunkSize == 0) break;
      final chunkStart = lineEnd + 2;
      final chunkEnd = chunkStart + chunkSize;
      if (chunkEnd > bytes.length) break;
      decoded.addAll(bytes.sublist(chunkStart, chunkEnd));
      offset = chunkEnd + 2;
    }
    return decoded;
  }

  static Future<http.Response?> tmdbSecureSocketGet(String host, String path, Map<String, String> headers) async {
    final ips = await resolveTmdbDoH(host);
    for (final ip in ips) {
      try {
        final rawSocket = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
        final secureSocket = await SecureSocket.secure(rawSocket, host: host);

        final reqHeaders = Map<String, String>.from(headers);
        reqHeaders['Host'] = host;
        reqHeaders['Connection'] = 'close';
        reqHeaders['Accept-Encoding'] = 'identity';

        final headerLines = reqHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
        secureSocket.write('GET $path HTTP/1.1\r\n$headerLines\r\n\r\n');
        await secureSocket.flush();

        final responseBytes = await secureSocket.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        secureSocket.destroy();

        int headerEnd = -1;
        for (int i = 0; i < responseBytes.length - 3; i++) {
          if (responseBytes[i] == 13 &&
              responseBytes[i + 1] == 10 &&
              responseBytes[i + 2] == 13 &&
              responseBytes[i + 3] == 10) {
            headerEnd = i;
            break;
          }
        }
        if (headerEnd == -1) continue;

        final headerStr = utf8.decode(responseBytes.sublist(0, headerEnd));
        final bodyBytes = responseBytes.sublist(headerEnd + 4);

        final statusLine = headerStr.split('\r\n').first.split(' ');
        final statusCode = int.tryParse(statusLine[1]) ?? 500;

        final respHeaders = <String, String>{};
        for (final line in headerStr.split('\r\n').skip(1)) {
          final idx = line.indexOf(':');
          if (idx != -1) {
            respHeaders[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 1).trim();
          }
        }

        List<int> finalBody = bodyBytes;
        if (respHeaders['transfer-encoding']?.toLowerCase() == 'chunked') {
          finalBody = decodeChunked(bodyBytes);
        }

        return http.Response.bytes(finalBody, statusCode, headers: respHeaders);
      } catch (_) {}
    }
    return null;
  }

  static Future<http.Response?> tmdbGet(String path, [Map<String, String>? queryParams]) async {
    final params = Map<String, String>.from(queryParams ?? {});
    final key = ApiConfig.tmdbApiKey.trim();
    if (key.isEmpty) return null;

    final headers = <String, String>{
      'accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    };

    if (key.startsWith('eyJ') || key.length > 50) {
      headers['Authorization'] = 'Bearer $key';
    } else {
      params['api_key'] = key;
    }

    final query = params.isNotEmpty ? Uri(queryParameters: params).query : '';
    final fullPath = query.isNotEmpty ? '/3$path?$query' : '/3$path';

    const hosts = ['api.themoviedb.org', 'api.tmdb.org'];
    for (final host in hosts) {
      // Primary: Always resolve via DNS-over-HTTPS (DoH)
      final response = await tmdbSecureSocketGet(host, fullPath, headers);
      if (response != null &&
          (response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 401)) {
        return response;
      }

      // Fallback: Standard HTTPS
      try {
        final uri = Uri.https(host, '/3$path', params.isNotEmpty ? params : null);
        final fallbackResp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));
        if (fallbackResp.statusCode == 200 || fallbackResp.statusCode == 404 || fallbackResp.statusCode == 401) {
          return fallbackResp;
        }
      } catch (_) {}
    }
    return null;
  }
}
