import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/stream_source.dart';

class StreamMetrics {
  final int ttfbMs;
  final double throughputMbPerSec;
  final double estimatedBitrateMbPerSec;
  final double headroomRatio;
  final bool isQualified;
  final int bytesTransferred;

  const StreamMetrics({
    required this.ttfbMs,
    required this.throughputMbPerSec,
    required this.estimatedBitrateMbPerSec,
    required this.headroomRatio,
    required this.isQualified,
    required this.bytesTransferred,
  });
}

class RankedStreamResult {
  final StreamSource topStream;
  final List<StreamSource> fallbackStreams;
  final List<StreamSource> unprobedStreams;
  final Map<String, StreamMetrics> metrics;
  final bool hasQualifiedStreams;

  const RankedStreamResult({
    required this.topStream,
    this.fallbackStreams = const [],
    this.unprobedStreams = const [],
    this.metrics = const {},
    this.hasQualifiedStreams = true,
  });
}

class StreamRanker {
  static final RegExp _sizeRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(GB|GiB|MB|MiB)', caseSensitive: false);

  static int? parseSizeBytes(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = _sizeRegex.firstMatch(text);
    if (match == null) return null;
    final val = double.tryParse(match.group(1) ?? '');
    if (val == null) return null;
    final unit = (match.group(2) ?? '').toUpperCase();
    if (unit.contains('G')) return (val * 1024 * 1024 * 1024).round();
    if (unit.contains('M')) return (val * 1024 * 1024).round();
    return null;
  }

  static double estimateBitrateMbPerSec(StreamSource stream, {int? runtimeMinutes}) {
    final runtimeSec = (runtimeMinutes != null && runtimeMinutes > 0) ? runtimeMinutes * 60 : 7200;
    int? sizeBytes = stream.sizeBytes;
    if (sizeBytes == null || sizeBytes <= 0) {
      final combined = '${stream.filename ?? ''} ${stream.formattedSize ?? ''}';
      sizeBytes = parseSizeBytes(combined);
    }
    if (sizeBytes != null && sizeBytes > 50 * 1024 * 1024) {
      return (sizeBytes / (1024 * 1024)) / runtimeSec;
    }
    final q = stream.quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) return 2.50;
    if (q.contains('1080')) return 0.75;
    if (q.contains('720')) return 0.35;
    if (q.contains('480') || q.contains('sd')) return 0.15;
    return 0.50;
  }

  static Future<StreamMetrics?> probeStream(
    StreamSource stream, {
    int? runtimeMinutes,
    http.Client? client,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.tryParse(stream.url);
      if (uri == null) return null;

      final headers = Map<String, String>.from(stream.headers ?? {});
      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      }

      final isManifest = stream.url.contains('.m3u8') || stream.url.contains('.mpd');
      if (!isManifest) {
        headers['Range'] = 'bytes=0-65535';
      }

      final request = http.Request('GET', uri)..headers.addAll(headers);
      final stopwatch = Stopwatch()..start();

      final streamedResponse = await httpClient.send(request).timeout(timeout);
      final ttfbMs = stopwatch.elapsedMilliseconds;

      final contentType = (streamedResponse.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('text/html')) {
        unawaited(streamedResponse.stream.drain());
        return null;
      }

      if (streamedResponse.statusCode >= 400 && streamedResponse.statusCode != 403 && streamedResponse.statusCode != 416) {
        unawaited(streamedResponse.stream.drain());
        return null;
      }

      final targetBytes = isManifest ? 16384 : 65536;
      final bytes = <int>[];
      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = streamedResponse.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (bytes.length >= targetBytes && !completer.isCompleted) {
            completer.complete();
            sub.cancel();
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      final elapsed = stopwatch.elapsedMilliseconds;
      final remainingMs = timeout.inMilliseconds - elapsed;
      if (remainingMs > 50) {
        await completer.future.timeout(Duration(milliseconds: remainingMs), onTimeout: () {
          sub.cancel();
        });
      } else {
        sub.cancel();
      }

      if (bytes.isEmpty) {
        return null;
      }

      final downloadDuration = (stopwatch.elapsedMilliseconds - ttfbMs) / 1000.0;
      final throughputMbPerSec = (bytes.length / (1024 * 1024)) / (downloadDuration > 0 ? downloadDuration : 0.001);

      final bitrate = estimateBitrateMbPerSec(stream, runtimeMinutes: runtimeMinutes);
      final headroom = bitrate > 0 ? throughputMbPerSec / bitrate : 1.0;

      final isMkv = stream.url.toLowerCase().contains('.mkv');
      final totalSize = stream.sizeBytes ?? parseSizeBytes('${stream.filename ?? ''} ${stream.formattedSize ?? ''}');
      final minHeadroom = (isMkv && (totalSize ?? 0) > 4 * 1024 * 1024 * 1024) ? 2.0 : 1.4;

      final isQualified = ttfbMs <= 2000 && headroom >= minHeadroom && bytes.isNotEmpty;

      return StreamMetrics(
        ttfbMs: ttfbMs,
        throughputMbPerSec: throughputMbPerSec,
        estimatedBitrateMbPerSec: bitrate,
        headroomRatio: headroom,
        isQualified: isQualified,
        bytesTransferred: bytes.length,
      );
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) httpClient.close();
    }
  }

  static int _qualityRank(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('2160')) return 4;
    if (q.contains('1080')) return 3;
    if (q.contains('720')) return 2;
    if (q.contains('480')) return 1;
    return 0;
  }

  static Future<RankedStreamResult> rankStreams(
    List<StreamSource> candidates, {
    int? runtimeMinutes,
    int maxProbes = 6,
    int targetQualified = 3,
    int batchSize = 2,
    Duration perStreamTimeout = const Duration(milliseconds: 1500),
    http.Client? client,
    void Function(String message, int probedCount, int qualifiedCount)? onProgress,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError('candidates list cannot be empty');
    }

    // Sort candidates by priority (ascending: 1 = top priority) and quality tier
    final sortedCandidates = List<StreamSource>.from(candidates)..sort((a, b) {
      if (a.priority != null && b.priority != null && a.priority != b.priority) {
        return a.priority!.compareTo(b.priority!);
      }
      if (a.priority != null && b.priority == null) return -1;
      if (a.priority == null && b.priority != null) return 1;
      return _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    });

    final qualified = <StreamSource>[];
    final metricsMap = <String, StreamMetrics>{};
    final unprobed = List<StreamSource>.from(sortedCandidates);
    final probedList = <StreamSource>[];
    int probedCount = 0;

    // Parallel batch probing
    while (unprobed.isNotEmpty && probedCount < maxProbes && qualified.length < targetQualified) {
      final currentBatch = <StreamSource>[];
      final remainingNeeded = targetQualified - qualified.length;
      final effectiveBatchSize = remainingNeeded < batchSize ? remainingNeeded : batchSize;

      while (unprobed.isNotEmpty && currentBatch.length < effectiveBatchSize && (probedCount + currentBatch.length) < maxProbes) {
        currentBatch.add(unprobed.removeAt(0));
      }

      final summary = currentBatch.map((s) => '${s.provider.toUpperCase()} ${s.quality}').join(', ');
      onProgress?.call('Probing $summary (${probedCount + currentBatch.length}/$maxProbes)...', probedCount + currentBatch.length, qualified.length);

      final probeFutures = currentBatch.map((s) => probeStream(
        s,
        runtimeMinutes: runtimeMinutes,
        client: client,
        timeout: perStreamTimeout,
      )).toList();

      final results = await Future.wait(probeFutures);
      for (int i = 0; i < currentBatch.length; i++) {
        final stream = currentBatch[i];
        final metrics = results[i];
        probedCount++;

        final headroom = metrics?.headroomRatio ?? 0.0;
        final enriched = stream.copyWith(headroomRatio: headroom);
        probedList.add(enriched);
        metricsMap[stream.url] = metrics ?? const StreamMetrics(
          ttfbMs: 9999,
          throughputMbPerSec: 0.0,
          estimatedBitrateMbPerSec: 0.0,
          headroomRatio: 0.0,
          isQualified: false,
          bytesTransferred: 0,
        );

        if (metrics != null && metrics.isQualified) {
          qualified.add(enriched);
          onProgress?.call('Qualified: ${stream.provider} ${stream.quality} (${headroom.toStringAsFixed(1)}x)', probedCount, qualified.length);
        }
      }

      if (qualified.length >= targetQualified) break;
    }

    final primaryQualified = List<StreamSource>.from(qualified);

    // Dynamic threshold relaxation: If standard headroom (1.4x / 2.0x) yielded fewer than targetQualified,
    // probe all remaining unprobed streams ("go till end") and relax headroom threshold to 1.1x then 1.0x.
    if (qualified.length < targetQualified && unprobed.isNotEmpty) {
      onProgress?.call('Probing all remaining sources to find stable playback streams...', probedCount, qualified.length);

      while (unprobed.isNotEmpty) {
        final currentBatch = <StreamSource>[];
        while (unprobed.isNotEmpty && currentBatch.length < batchSize) {
          currentBatch.add(unprobed.removeAt(0));
        }

        final summary = currentBatch.map((s) => '${s.provider.toUpperCase()} ${s.quality}').join(', ');
        onProgress?.call('Probing $summary (${probedCount + currentBatch.length}/${sortedCandidates.length})...', probedCount + currentBatch.length, qualified.length);

        final probeFutures = currentBatch.map((s) => probeStream(
          s,
          runtimeMinutes: runtimeMinutes,
          client: client,
          timeout: perStreamTimeout,
        )).toList();

        final results = await Future.wait(probeFutures);
        for (int i = 0; i < currentBatch.length; i++) {
          final stream = currentBatch[i];
          final metrics = results[i];
          probedCount++;

          final headroom = metrics?.headroomRatio ?? 0.0;
          final enriched = stream.copyWith(headroomRatio: headroom);
          probedList.add(enriched);
          metricsMap[stream.url] = metrics ?? const StreamMetrics(
            ttfbMs: 9999,
            throughputMbPerSec: 0.0,
            estimatedBitrateMbPerSec: 0.0,
            headroomRatio: 0.0,
            isQualified: false,
            bytesTransferred: 0,
          );

          if (metrics != null && metrics.isQualified && !qualified.any((q) => q.url == stream.url)) {
            qualified.add(enriched);
            onProgress?.call('Qualified: ${stream.provider} ${stream.quality} (${headroom.toStringAsFixed(1)}x)', probedCount, qualified.length);
          }
        }
      }
    }

    // If still fewer than targetQualified, relax headroom bar to 1.1x, then 1.0x from all probed streams
    if (qualified.length < targetQualified) {
      for (final threshold in [1.1, 1.0]) {
        for (final stream in probedList) {
          final m = metricsMap[stream.url];
          if (m != null && m.headroomRatio >= threshold && m.ttfbMs <= 2500) {
            if (!qualified.any((s) => s.url == stream.url)) {
              qualified.add(stream);
              if (qualified.length >= targetQualified) break;
            }
          }
        }
        if (qualified.length >= targetQualified) break;
      }
    }

    List<StreamSource> getRemainingStreams(StreamSource top, List<StreamSource> fallbacks) {
      final selectedUrls = {top.url, ...fallbacks.map((f) => f.url)};
      return sortedCandidates
          .where((s) => !selectedUrls.contains(s.url))
          .map((s) {
            final m = metricsMap[s.url];
            return m != null ? s.copyWith(headroomRatio: m.headroomRatio) : s;
          })
          .toList();
    }

    if (qualified.isNotEmpty) {
      final top = qualified.first;
      final fallbacks = List<StreamSource>.from(qualified.sublist(1));
      if (fallbacks.length < 2) {
        for (final s in sortedCandidates) {
          if (s.url != top.url && !fallbacks.any((f) => f.url == s.url)) {
            final m = metricsMap[s.url];
            fallbacks.add(m != null ? s.copyWith(headroomRatio: m.headroomRatio) : s);
            if (fallbacks.length >= 2) break;
          }
        }
      }
      return RankedStreamResult(
        topStream: top,
        fallbackStreams: fallbacks,
        unprobedStreams: getRemainingStreams(top, fallbacks),
        metrics: metricsMap,
        hasQualifiedStreams: primaryQualified.isNotEmpty,
      );
    }

    // Graceful degradation when no stream met even 1.0x: pick highest calculated headroom
    if (metricsMap.isNotEmpty) {
      final sortedByHeadroom = probedList.where((s) => metricsMap.containsKey(s.url)).toList()
        ..sort((a, b) => (metricsMap[b.url]?.headroomRatio ?? 0).compareTo(metricsMap[a.url]?.headroomRatio ?? 0));
      if (sortedByHeadroom.isNotEmpty) {
        final best = sortedByHeadroom.first;
        final fallbacks = sortedByHeadroom.skip(1).take(2).toList();
        return RankedStreamResult(
          topStream: best,
          fallbackStreams: fallbacks,
          unprobedStreams: getRemainingStreams(best, fallbacks),
          metrics: metricsMap,
          hasQualifiedStreams: false,
        );
      }
    }

    // Default fallback to first candidate if network probe was blocked or errored
    final defaultTop = sortedCandidates.first;
    final defaultFallbacks = sortedCandidates.skip(1).take(2).toList();
    return RankedStreamResult(
      topStream: defaultTop,
      fallbackStreams: defaultFallbacks,
      unprobedStreams: getRemainingStreams(defaultTop, defaultFallbacks),
      metrics: metricsMap,
      hasQualifiedStreams: false,
    );
  }

  static Future<StreamSource?> findNextFallback(
    List<StreamSource> unprobedStreams, {
    int? runtimeMinutes,
    Duration timeout = const Duration(milliseconds: 2500),
    http.Client? client,
  }) async {
    final pool = List<StreamSource>.from(unprobedStreams);
    StreamSource? bestCandidate;
    double highestHeadroom = -1;

    while (pool.isNotEmpty) {
      final candidate = pool.removeAt(0);
      final metrics = await probeStream(
        candidate,
        runtimeMinutes: runtimeMinutes,
        client: client,
        timeout: timeout,
      );
      final headroom = metrics?.headroomRatio ?? 0.0;
      final enriched = candidate.copyWith(headroomRatio: headroom);
      if (metrics != null && metrics.isQualified) {
        return enriched;
      }
      if (headroom > highestHeadroom) {
        highestHeadroom = headroom;
        bestCandidate = enriched;
      }
    }
    return bestCandidate;
  }

  static Future<bool> checkInternetReachability({
    http.Client? client,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.parse('http://clients3.google.com/generate_204');
      final res = await httpClient.get(uri).timeout(timeout);
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (shouldClose) httpClient.close();
    }
  }
}
