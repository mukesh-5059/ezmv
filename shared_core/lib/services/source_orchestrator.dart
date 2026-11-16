import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import '../models/stream_progress_event.dart';
import '../models/stream_source.dart';
import 'stream_priority.dart';
import 'stream_ranker.dart';

class MediaScrapeTarget {
  final String imdbId;
  final String title;
  final String mediaType;
  final int? season;
  final int? episode;
  final int? year;
  final String? originalLanguage;
  final String? defaultLanguage;
  final List<String> genres;

  const MediaScrapeTarget({
    required this.imdbId,
    required this.title,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.year,
    this.originalLanguage,
    this.defaultLanguage,
    this.genres = const [],
  });

  String get searchTitle {
    if (mediaType == 'tv') {
      final clean = title
          .replaceAll(RegExp(r'\s+S\d+E\d+.*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+Season\s*\d+.*$', caseSensitive: false), '')
          .trim();
      return clean.isNotEmpty ? clean : title;
    }
    return title;
  }

  Map<String, dynamic> toJson() => {
    'imdbId': imdbId,
    'title': searchTitle,
    'displayTitle': title,
    'mediaType': mediaType,
    'season': season ?? 1,
    'episode': episode ?? 1,
    'year': year,
    'originalLanguage': originalLanguage,
    'defaultLanguage': defaultLanguage,
    'genres': genres,
  };
}

class BatchPlan {
  final int batchNumber;
  final List<Map<String, dynamic>> stremioAddons;
  final List<Map<String, dynamic>> jsExtractors;

  const BatchPlan({
    required this.batchNumber,
    required this.stremioAddons,
    required this.jsExtractors,
  });

  bool get isEmpty => stremioAddons.isEmpty && jsExtractors.isEmpty;
}

class BatchScrapeResult {
  final int batchNumber;
  final int totalBatches;
  final List<StreamSource> streams;
  final bool hasQualifiedStreams;
  final bool hasMoreBatches;

  const BatchScrapeResult({
    required this.batchNumber,
    required this.totalBatches,
    required this.streams,
    this.hasQualifiedStreams = false,
    required this.hasMoreBatches,
  });
}

class SourceOrchestrator {
  final Map<String, dynamic> config;
  final String routerCode;
  final Map<String, String> scriptRegistry;
  final http.Client _httpClient;

  SourceOrchestrator({
    Map<String, dynamic>? config,
    String? routerCode,
    Map<String, String>? scriptRegistry,
    http.Client? httpClient,
  })  : config = config ?? defaultSourcesConfig,
        routerCode = routerCode ?? defaultRouterCode,
        scriptRegistry = scriptRegistry ?? {},
        _httpClient = httpClient ?? ApiClient.instance.httpClient;

  static const String defaultRouterCode = r'''
function routeMedia(media, config) {
  var genres = (media && media.genres) || [];
  var lang = (media && media.originalLanguage || '').toLowerCase();
  var mediaType = (media && media.mediaType || 'movie').toLowerCase();

  var isAnime = genres.some(function(g) {
    var s = String(g).toLowerCase();
    return s === 'anime' || s === 'animation';
  }) && (lang === 'ja' || genres.some(function(g) { return String(g).toLowerCase() === 'anime'; }) || !lang);

  function matches(source) {
    if (!source || source.enabled === false) return false;
    var m = source.match || {};
    if (m.media_types && m.media_types.length) {
      if (m.media_types.indexOf(mediaType) === -1) return false;
    }
    if (m.genres && m.genres.length) {
      var genreMatch = m.genres.some(function(mg) {
        if (mg === 'anime' && isAnime) return true;
        return genres.some(function(g) { return String(g).toLowerCase() === mg.toLowerCase(); });
      });
      if (!genreMatch) return false;
    }
    if (m.original_languages && m.original_languages.length) {
      if (!isAnime && (!lang || m.original_languages.indexOf(lang) === -1)) return false;
    }
    return true;
  }

  var addons = (config.stremio_addons || []).filter(matches);
  var extractors = (config.js_extractors || []).filter(matches);

  var batchMap = {};
  function addSource(s, type) {
    var b = s.batch || s.priority || 1;
    if (!batchMap[b]) {
      batchMap[b] = { batchNumber: b, stremio_addons: [], js_extractors: [] };
    }
    if (type === 'addon') batchMap[b].stremio_addons.push(s);
    else batchMap[b].js_extractors.push(s);
  }

  addons.forEach(function(s) { addSource(s, 'addon'); });
  extractors.forEach(function(s) { addSource(s, 'extractor'); });

  var batchNums = Object.keys(batchMap).map(Number).sort(function(a, b) { return a - b; });
  return batchNums.map(function(num) {
    var b = batchMap[num];
    b.stremio_addons.sort(function(a, b) { return (a.priority || 10) - (b.priority || 10); });
    b.js_extractors.sort(function(a, b) { return (a.priority || 10) - (b.priority || 10); });
    return b;
  });
}
''';

  static const String ezmvPreambleJs = r'''
var _b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
if (typeof btoa === 'undefined') {
  globalThis.btoa = function(input) {
    var str = String(input);
    var output = '';
    for (var block = 0, charCode, i = 0, map = _b64chars;
        str.charAt(i | 0) || (map = '=', i % 1);
        output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
      charCode = str.charCodeAt(i += 3/4);
      if (charCode > 0xFF) throw new Error("'btoa' failed");
      block = block << 8 | charCode;
    }
    return output;
  };
}
if (typeof atob === 'undefined') {
  globalThis.atob = function(input) {
    var str = String(input).replace(/=+$/, '');
    if (str.length % 4 === 1) throw new Error("'atob' failed");
    var output = '';
    for (var bc = 0, bs, buffer, i = 0;
        buffer = str.charAt(i++);
        ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
          bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
      buffer = _b64chars.indexOf(buffer);
    }
    return output;
  };
}
if (typeof htmlText === 'undefined') {
  globalThis.htmlText = function(str) {
    if (!str) return '';
    return String(str)
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&nbsp;/g, ' ')
      .trim();
  };
}
if (typeof base64ToBytes === 'undefined') {
  globalThis.base64ToBytes = function(b64) {
    var bin = atob(String(b64 || ''));
    var bytes = [];
    for (var i = 0; i < bin.length; i++) bytes.push(bin.charCodeAt(i));
    return bytes;
  };
}
if (typeof bytesToBase64 === 'undefined') {
  globalThis.bytesToBase64 = function(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  };
}
if (typeof absUrl === 'undefined') {
  globalThis.absUrl = function(path, base) {
    if (!path) return '';
    if (/^https?:\/\//i.test(path)) return path;
    base = (base || '').replace(/\/+$/, '');
    path = String(path).replace(/^\/+/, '');
    return base + '/' + path;
  };
}
globalThis.__ezmv_req_id = 0;
globalThis.__ezmv_callbacks = {};
var _ezmvFormat = function(args) {
  var parts = [];
  for (var i = 0; i < args.length; i++) {
    var a = args[i];
    if (a === null) { parts.push('null'); }
    else if (a === undefined) { parts.push('undefined'); }
    else if (typeof a === 'object') {
      try { parts.push(JSON.stringify(a)); } catch (e) { parts.push(String(a)); }
    } else {
      parts.push(String(a));
    }
  }
  return parts.join(' ');
};
globalThis.console = {
  log: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'INFO', msg: _ezmvFormat(arguments) }));
  },
  warn: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'WARN', msg: _ezmvFormat(arguments) }));
  },
  error: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'ERROR', msg: _ezmvFormat(arguments) }));
  },
  info: function() {
    sendMessage('ezmv_log', JSON.stringify({ level: 'INFO', msg: _ezmvFormat(arguments) }));
  }
};
globalThis.__ezmv_resolve = function(id, res) {
  if (globalThis.__ezmv_callbacks && globalThis.__ezmv_callbacks[id]) {
    res.text = function() { return Promise.resolve(res.body); };
    res.json = function() { return Promise.resolve(JSON.parse(res.body)); };
    globalThis.__ezmv_callbacks[id].resolve(res);
    delete globalThis.__ezmv_callbacks[id];
  }
};
globalThis.__ezmv_reject = function(id, err) {
  if (globalThis.__ezmv_callbacks && globalThis.__ezmv_callbacks[id]) {
    globalThis.__ezmv_callbacks[id].reject(new Error(err));
    delete globalThis.__ezmv_callbacks[id];
  }
};
globalThis.fetch = function(url, options) {
  options = options || {};
  return new Promise(function(resolve, reject) {
    var id = ++globalThis.__ezmv_req_id;
    globalThis.__ezmv_callbacks[id] = { resolve: resolve, reject: reject };
    sendMessage('ezmv_fetch', JSON.stringify({
      id: id,
      url: url,
      method: options.method || 'GET',
      headers: options.headers || {},
      body: options.body || null
    }));
  });
};
globalThis.fetch._ezmv = true;
globalThis.__ezmv_run_scrape = function(targetJsonStr) {
  return Promise.resolve()
    .then(function() {
      var target = (typeof targetJsonStr === 'string') ? JSON.parse(targetJsonStr) : targetJsonStr;
      return scrape(target);
    })
    .then(function(res) {
      return JSON.stringify(res || []);
    })
    .catch(function(err) {
      console.error('[EZMV_SCRAPE_ERROR]', (err && err.stack) || err);
      return JSON.stringify([]);
    });
};
''';

  static const Map<String, dynamic> defaultSourcesConfig = {
    'version': 1,
    'stremio_addons': [
      {
        'id': 'hdhub_addon',
        'name': 'HDHub (Addon)',
        'manifest_url':
            'https://hdhub.thevolecitor.qzz.io/eyJ0b3Jib3giOiJ1bnNldCIsInF1YWxpdGllcyI6IjEwODBwLDcyMHAsNDgwcCIsInNvcnQiOiJkZXNjIiwiY2F0YWxvZ3MiOiIifQ/manifest.json',
        'enabled': true,
        'batch': 1,
        'priority': 1,
        'match': <String, dynamic>{},
      },
      {
        'id': 'penguplay',
        'name': 'PenguPlay (Addon)',
        'manifest_url':
            'https://pengu.uk/%7B%22auth_token%22%3A%22p30MBIC3MSN4Dbh5ZGDeVyGUzMoFFJUBEL4FNv36DWY%22%7D/manifest.json',
        'enabled': true,
        'batch': 2,
        'priority': 1,
        'match': <String, dynamic>{},
      },
      {
        'id': 'plaviohd',
        'name': 'PlavioHD (Addon)',
        'manifest_url':
            'https://hd.plavio.site/c/eyJwcm92aWRlcnMiOlsiSERIdWI0dSIsIkNpbmV6byIsIlZlZ2Ftb3ZpZXMiLCJNb3ZpZXNIdW50IiwiNEtIREh1YiIsIk9uZVRvdWNoVFYiLCJWaWRyb2NrIiwiU3BhY2VEb20iLCJXYXkyTW92aWVzIiwiRmxpeE5lc3QiLCJIREh1YiIsIk1vdmllczR1IiwiQ05DVmVyc2UiLCJNb3ZpZUJveCIsIkRlZXBGbGl4Il0sInFzZXQiOlsiMTA4MHAiLCI3MjBwIiwiNDgwcCIsIjM2MHAiLCJIRFRTIiwiQ0FNIiwiSERSaXAiXSwiY3R5cGVzIjpbIm1vdmllIiwid2Vic2VyaWVzIiwidHYiLCJhbmltZSJdLCJsYW5nUGljayI6WyJIaW5kaSIsIkVuZ2xpc2giLCJQdW5qYWJpIiwiQmVuZ2FsaSIsIlRhbWlsIiwiVGVsdWd1IiwiTWFsYXlhbGFtIiwiS2FubmFkYSIsIk1hcmF0aGkiLCJEdWFsIEF1ZGlvIiwiTXVsdGkgQXVkaW8iLCJBcmFiaWMiLCJTcGFuaXNoIiwiRnJlbmNoIiwiR2VybWFuIiwiSXRhbGlhbiIsIlBvcnR1Z3Vlc2UiLCJSdXNzaWFuIiwiSmFwYW5lc2UiLCJJbmRvbmVzaWFuIiwiRHV0Y2giLCJIdW5nYXJpYW4iXSwic29ydE5ldyI6InNpemVRdWFsaXR5IiwiaW5jSGRyIjp0cnVlLCJpbmNIZXZjIjp0cnVlLCJpbmNEdWFsIjp0cnVlLCJpbmNNdWx0aSI6dHJ1ZX0/manifest.json',
        'enabled': true,
        'batch': 3,
        'priority': 1,
        'match': <String, dynamic>{},
      },
      {
        'id': 'notorrent',
        'name': 'NoTorrent (Addon)',
        'manifest_url': 'https://addon.notorrent2.workers.dev/manifest.json',
        'enabled': true,
        'batch': 4,
        'priority': 1,
        'match': <String, dynamic>{},
      },
    ],
    'js_extractors': [
      {
        'id': 'hianime',
        'name': 'HiAnime (Scraper)',
        'script_url': 'hianime.js',
        'interface': 'ezmv',
        'enabled': true,
        'batch': 1,
        'priority': 1,
        'match': {
          'genres': ['anime', 'animation'],
          'original_languages': ['ja'],
        },
      },
      {
        'id': 'gogo',
        'name': 'AniGoGo (Scraper)',
        'script_url': 'gogo.js',
        'interface': 'ezmv',
        'enabled': true,
        'batch': 1,
        'priority': 2,
        'match': {
          'genres': ['anime', 'animation'],
          'original_languages': ['ja'],
        },
      },
      {
        'id': 'hdhub_scraper',
        'name': 'HDHub4u (Scraper)',
        'script_url': 'hdhub.js',
        'interface': 'ezmv',
        'enabled': true,
        'batch': 1,
        'priority': 2,
        'match': <String, dynamic>{},
      },
      {
        'id': '4khdhub',
        'name': '4K HDHub (Scraper)',
        'script_url': '4khdhub.js',
        'interface': 'ezmv',
        'enabled': true,
        'batch': 1,
        'priority': 3,
        'match': <String, dynamic>{},
      },
    ],
  };

  List<BatchPlan> planBatches(MediaScrapeTarget target) {
    JavascriptRuntime? runtime;
    try {
      runtime = getJavascriptRuntime();
      runtime.evaluate(routerCode);
      final mediaJson = json.encode(target.toJson());
      final configJson = json.encode(config);
      final res = runtime.evaluate('JSON.stringify(routeMedia($mediaJson, $configJson))');
      if (res.isError) throw Exception(res.stringResult);
      final rawList = json.decode(res.stringResult) as List? ?? [];
      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        final bNum = (map['batchNumber'] as num?)?.toInt() ?? 1;
        final addons = (map['stremio_addons'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final extractors = (map['js_extractors'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return BatchPlan(
          batchNumber: bNum,
          stremioAddons: addons,
          jsExtractors: extractors,
        );
      }).toList();
    } catch (_) {
      return _fallbackPlanBatches(target);
    } finally {
      runtime?.dispose();
    }
  }

  List<BatchPlan> _fallbackPlanBatches(MediaScrapeTarget target) {
    final addons = (config['stremio_addons'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => _fallbackMatches(s, target));

    final extractors = (config['js_extractors'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((s) => _fallbackMatches(s, target));

    final batchMap = <int, BatchPlan>{};

    void addSource(Map<String, dynamic> s, bool isAddon) {
      final b = (s['batch'] ?? s['priority'] ?? 1) as int;
      final plan = batchMap.putIfAbsent(
        b,
        () => BatchPlan(batchNumber: b, stremioAddons: [], jsExtractors: []),
      );
      if (isAddon) {
        plan.stremioAddons.add(s);
      } else {
        plan.jsExtractors.add(s);
      }
    }

    for (final a in addons) {
      addSource(a, true);
    }
    for (final ex in extractors) {
      addSource(ex, false);
    }

    final sortedBatchNums = batchMap.keys.toList()..sort();
    return sortedBatchNums.map((n) {
      final plan = batchMap[n]!;
      plan.stremioAddons.sort((a, b) => ((a['priority'] ?? 10) as int).compareTo((b['priority'] ?? 10) as int));
      plan.jsExtractors.sort((a, b) => ((a['priority'] ?? 10) as int).compareTo((b['priority'] ?? 10) as int));
      return plan;
    }).toList();
  }

  static bool _fallbackMatches(Map<String, dynamic> source, MediaScrapeTarget target) {
    if (source['enabled'] == false) return false;
    final m = source['match'] as Map<String, dynamic>? ?? {};

    final isAnime = target.genres.any((g) {
      final s = g.toLowerCase();
      return s == 'anime' || s == 'animation';
    }) && (target.originalLanguage?.toLowerCase() == 'ja' ||
           target.genres.any((g) => g.toLowerCase() == 'anime') ||
           target.originalLanguage == null ||
           target.originalLanguage!.isEmpty);

    final mediaTypes = (m['media_types'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (mediaTypes != null && mediaTypes.isNotEmpty) {
      if (!mediaTypes.contains(target.mediaType.toLowerCase())) return false;
    }

    final genres = (m['genres'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (genres != null && genres.isNotEmpty) {
      final genreMatch = genres.any((mg) {
        if (mg == 'anime' && isAnime) return true;
        return target.genres.any((g) => g.toLowerCase() == mg);
      });
      if (!genreMatch) return false;
    }

    final origLangs = (m['original_languages'] as List?)?.map((e) => e.toString().toLowerCase()).toList();
    if (origLangs != null && origLangs.isNotEmpty) {
      final lang = target.originalLanguage?.toLowerCase();
      if (!isAnime && (lang == null || !origLangs.contains(lang))) return false;
    }

    return true;
  }

  Future<List<StreamSource>> _fetchStremioAddon(
    Map<String, dynamic> addon,
    MediaScrapeTarget target,
  ) async {
    final manifestUrl = addon['manifest_url'] as String? ?? '';
    final id = addon['id'] as String? ?? 'addon';
    if (manifestUrl.isEmpty) return [];

    final baseUrl = manifestUrl.replaceAll(RegExp(r'/manifest\.json/?$'), '');
    final streamPath = (target.mediaType == 'tv' && target.season != null && target.episode != null)
        ? '/stream/series/${target.imdbId}:${target.season}:${target.episode}.json'
        : '/stream/movie/${target.imdbId}.json';

    final uri = Uri.parse('$baseUrl$streamPath');
    try {
      final res = await _httpClient.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final data = json.decode(res.body) as Map<String, dynamic>?;
      final rawStreams = data?['streams'] as List? ?? [];

      final out = <StreamSource>[];
      for (final raw in rawStreams) {
        if (raw is Map<String, dynamic>) {
          final s = StreamPriorityCalculator.parseStremioStream(
            raw,
            provider: id,
            defaultLanguage: target.defaultLanguage,
            originalLanguage: target.originalLanguage,
          );
          if (s != null) out.add(s);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<StreamSource>> _runJsExtractor(
    Map<String, dynamic> extractor,
    MediaScrapeTarget target,
  ) async {
    if (io.Platform.environment.containsKey('FLUTTER_TEST') && !scriptRegistry.containsKey('test_enable_js')) {
      return [];
    }

    final scriptUrl = extractor['script_url'] as String? ?? '';
    var code = scriptRegistry[scriptUrl] ?? scriptRegistry[extractor['id']];
    if (code == null || code.trim().isEmpty) {
      final filename = scriptUrl.isNotEmpty ? scriptUrl : '${extractor['id']}.js';
      try {
        code = await rootBundle.loadString('assets/sources/$filename');
      } catch (_) {
        try {
          final f = io.File('sources/$filename');
          if (f.existsSync()) code = await f.readAsString();
        } catch (_) {}
      }
      if (code != null && code.isNotEmpty) {
        scriptRegistry[scriptUrl] = code;
        scriptRegistry[extractor['id']] = code;
      }
    }
    if (code == null || code.trim().isEmpty) return [];

    final extractorId = extractor['id'] ?? 'js';
    JavascriptRuntime? runtime;
    try {
      runtime = getJavascriptRuntime(xhr: false);
      runtime.onMessage('ezmv_log', (dynamic rawArgs) {
        try {
          final args = rawArgs is String ? json.decode(rawArgs) : rawArgs;
          final level = args['level'] ?? 'INFO';
          final msg = args['msg'] ?? '';
          print('[$extractorId][$level] $msg');
        } catch (_) {
          print('[$extractorId] $rawArgs');
        }
      });
      runtime.onMessage('ezmv_fetch', (dynamic rawArgs) async {
        try {
          final args = rawArgs is String ? json.decode(rawArgs) : rawArgs;
          final id = args['id'];
          final url = args['url'] as String;
          final method = (args['method'] as String? ?? 'GET').toUpperCase();
          print('[$extractorId][FETCH] $method $url');
          final headers = <String, String>{};
          if (args['headers'] is Map) {
            (args['headers'] as Map).forEach((k, v) => headers[k.toString()] = v.toString());
          }
          final body = args['body'];
          final req = http.Request(method, Uri.parse(url));
          headers.forEach((k, v) => req.headers[k] = v);
          if (body != null) req.body = body.toString();
          final streamed = await _httpClient.send(req);
          final resp = await http.Response.fromStream(streamed);
          print('[$extractorId][FETCH -> ${resp.statusCode}] $url (${resp.body.length} bytes)');
          final resData = json.encode({
            'status': resp.statusCode,
            'body': resp.body,
            'headers': resp.headers,
          });
          runtime?.evaluate('globalThis.__ezmv_resolve($id, $resData);');
        } catch (e) {
          print('[$extractorId][FETCH ERROR] $e');
          try {
            final args = rawArgs is String ? json.decode(rawArgs) : rawArgs;
            final id = args['id'];
            runtime?.evaluate('globalThis.__ezmv_reject($id, ${json.encode(e.toString())});');
          } catch (_) {}
        }
      });
      runtime.evaluate(ezmvPreambleJs);
      final evalInit = runtime.evaluate(code);
      if (evalInit.isError) {
        print('[$extractorId][EVAL SCRIPT ERROR] ${evalInit.stringResult}');
        return [];
      }

      print('[$extractorId] Starting scrape for "${target.title}" (season: ${target.season}, episode: ${target.episode})...');
      final targetJson = json.encode(target.toJson());
      final evalResult = runtime.evaluate('globalThis.__ezmv_run_scrape(${json.encode(targetJson)})');
      if (evalResult.isError) {
        print('[$extractorId][EVAL SCRAPE ERROR] ${evalResult.stringResult}');
        return [];
      }
      final resolved = await runtime.handlePromise(evalResult);
      if (resolved.isError) {
        print('[$extractorId][PROMISE ERROR] ${resolved.stringResult}');
        return [];
      }
      print('[$extractorId] Scrape resolved. Raw result preview: ${resolved.stringResult.length > 200 ? resolved.stringResult.substring(0, 200) + '...' : resolved.stringResult}');

      final out = <StreamSource>[];
      List<dynamic> items = [];
      try {
        final decoded = json.decode(resolved.stringResult);
        if (decoded is List) {
          items = decoded;
        } else if (decoded is String) {
          final d2 = json.decode(decoded);
          if (d2 is List) items = d2;
        }
      } catch (e) {
        print('[$extractorId] JSON decode error: $e');
        if (resolved.rawResult is List) {
          items = resolved.rawResult as List;
        }
      }
      print('[$extractorId] Parsed ${items.length} stream candidate(s)');

      for (final item in items) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final url = map['url']?.toString();
          if (url == null || !url.startsWith('http')) continue;

          final quality = map['quality']?.toString() ?? 'Auto';
          final headers = <String, String>{};
          if (map['headers'] is Map) {
            (map['headers'] as Map).forEach((k, v) => headers[k.toString()] = v.toString());
          }

          final priority = StreamPriorityCalculator.calculatePriority(
            provider: extractor['id'] ?? 'js',
            quality: quality,
            defaultLanguage: target.defaultLanguage,
            originalLanguage: target.originalLanguage,
          );

          out.add(StreamSource(
            url: url,
            quality: quality,
            provider: extractor['id'] ?? 'js',
            headers: headers,
            priority: priority,
          ));
        }
      }
      print('[$extractorId] Returning ${out.length} valid stream source(s)');
      return out;
    } catch (e, stack) {
      print('[$extractorId][EXCEPTION] $e\n$stack');
      return [];
    } finally {
      runtime?.dispose();
    }
  }

  Future<BatchScrapeResult> scrapeBatch({
    required MediaScrapeTarget target,
    required int batchNumber,
    void Function(String message)? onProgress,
    void Function(String provider, StreamProgressStatus status, int count)? onProviderStatus,
    void Function(ProbingStageEvent event)? onStageProgress,
  }) async {
    final plans = planBatches(target);
    final totalBatches = plans.isEmpty ? 1 : plans.length;
    final plan = plans.firstWhere(
      (p) => p.batchNumber == batchNumber,
      orElse: () => BatchPlan(batchNumber: batchNumber, stremioAddons: [], jsExtractors: []),
    );

    if (plan.isEmpty) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: [],
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }

    print('[SourceOrchestrator] Running Batch $batchNumber/$totalBatches for "${target.title}" (stremio: ${plan.stremioAddons.map((a) => a['id']).toList()}, js: ${plan.jsExtractors.map((e) => e['id']).toList()})');
    onProgress?.call('Querying Batch $batchNumber sources...');

    final futures = <Future<List<StreamSource>>>[];
    for (final addon in plan.stremioAddons) {
      final name = addon['name'] as String? ?? addon['id'] as String? ?? 'Stremio';
      onProviderStatus?.call(name, StreamProgressStatus.searching, 0);
      futures.add(_fetchStremioAddon(addon, target).then((res) {
        onProviderStatus?.call(name, StreamProgressStatus.resolved, res.length);
        return res;
      }).catchError((_) {
        onProviderStatus?.call(name, StreamProgressStatus.error, 0);
        return <StreamSource>[];
      }));
    }
    for (final extractor in plan.jsExtractors) {
      final name = extractor['name'] as String? ?? extractor['id'] as String? ?? 'JS Extractor';
      onProviderStatus?.call(name, StreamProgressStatus.searching, 0);
      futures.add(_runJsExtractor(extractor, target).then((res) {
        onProviderStatus?.call(name, StreamProgressStatus.resolved, res.length);
        return res;
      }).catchError((_) {
        onProviderStatus?.call(name, StreamProgressStatus.error, 0);
        return <StreamSource>[];
      }));
    }

    final results = await Future.wait(futures);
    final allCandidates = <StreamSource>[];
    for (final list in results) {
      allCandidates.addAll(list);
    }

    if (allCandidates.isEmpty) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: [],
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }

    // Sort all candidates by speed if known, then quality tier
    allCandidates.sort(StreamRanker.compareBySpeed);

    onProgress?.call('Ranking streams (${allCandidates.length} found)...');

    try {
      final ranked = await StreamRanker.rankStreams(
        allCandidates,
        maxProbes: 6,
        targetQualified: 3,
        batchSize: 2,
        client: _httpClient,
        onProgress: (msg, probed, qual) => onProgress?.call(msg),
        onStageProgress: onStageProgress,
      );

      final finalStreams = [
        ranked.topStream,
        ...ranked.fallbackStreams,
        ...ranked.unprobedStreams,
        ...ranked.failedStreams,
      ];

      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: finalStreams,
        hasQualifiedStreams: ranked.hasQualifiedStreams,
        hasMoreBatches: batchNumber < totalBatches,
      );
    } catch (_) {
      return BatchScrapeResult(
        batchNumber: batchNumber,
        totalBatches: totalBatches,
        streams: allCandidates,
        hasQualifiedStreams: false,
        hasMoreBatches: batchNumber < totalBatches,
      );
    }
  }

  Future<List<StreamSource>> scrapeWithBackendFallback({
    required MediaScrapeTarget target,
    void Function(String message)? onProgress,
    void Function(String provider, StreamProgressStatus status, int count)? onProviderStatus,
    void Function(ProbingStageEvent event)? onStageProgress,
  }) async {
    final batch1 = await scrapeBatch(
      target: target,
      batchNumber: 1,
      onProgress: onProgress,
      onProviderStatus: onProviderStatus,
      onStageProgress: onStageProgress,
    );

    if (batch1.streams.isNotEmpty) {
      return batch1.streams;
    }

    onProgress?.call('Connecting to backend fallback scrapers...');
    try {
      final completer = Completer<List<StreamSource>>();
      final stream = ApiClient.instance.getStreamsProgressive(
        target.mediaType,
        target.imdbId,
        season: target.season,
        episode: target.episode,
        originalLanguage: target.originalLanguage,
        defaultLanguage: target.defaultLanguage,
      );

      stream.listen(
        (event) {
          if (event.isDone) {
            if (event.status == StreamProgressStatus.error) {
              if (!completer.isCompleted) completer.completeError(Exception(event.error ?? 'Failed to fetch streams'));
            } else {
              if (!completer.isCompleted) completer.complete(event.streams ?? []);
            }
            return;
          }
          if (event.status == StreamProgressStatus.error) {
            if (event.provider == 'all') {
              if (!completer.isCompleted) {
                completer.completeError(Exception(event.error ?? 'Failed to fetch streams'));
              }
            } else {
              onProviderStatus?.call(event.provider, StreamProgressStatus.error, 0);
            }
          } else if (event.status == StreamProgressStatus.searching) {
            onProgress?.call('${event.provider}: searching...');
            onProviderStatus?.call(event.provider, StreamProgressStatus.searching, 0);
          } else if (event.status == StreamProgressStatus.resolved) {
            onProgress?.call('${event.provider}: resolved (${event.count ?? 0})');
            onProviderStatus?.call(event.provider, StreamProgressStatus.resolved, event.count ?? 0);
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      final fallbackStreams = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => [],
      );

      if (fallbackStreams.isNotEmpty) {
        return fallbackStreams;
      }
    } catch (err) {
      if (batch1.streams.isEmpty) rethrow;
    }

    return batch1.streams;
  }
}
