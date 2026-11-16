import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/stream_progress_event.dart';
import '../models/stream_source.dart';

class StreamMetrics {
  final int ttfbMs;
  final double throughputMbPerSec;
  final double estimatedBitrateMbPerSec;
  final double headroomRatio;
  final bool isQualified;
  final int bytesTransferred;
  final String? explicitError;

  const StreamMetrics({
    required this.ttfbMs,
    required this.throughputMbPerSec,
    required this.estimatedBitrateMbPerSec,
    required this.headroomRatio,
    required this.isQualified,
    required this.bytesTransferred,
    this.explicitError,
  });
}

class RankedStreamResult {
  final StreamSource topStream;
  final List<StreamSource> fallbackStreams;
  final List<StreamSource> unprobedStreams;
  final List<StreamSource> failedStreams;
  final Map<String, StreamMetrics> metrics;
  final bool hasQualifiedStreams;

  const RankedStreamResult({
    required this.topStream,
    this.fallbackStreams = const [],
    this.unprobedStreams = const [],
    this.failedStreams = const [],
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

  static Future<StreamSource> checkStreamHealth(
    StreamSource stream, {
    http.Client? client,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final httpClient = client ?? http.Client();
    final shouldClose = client == null;
    try {
      final uri = Uri.tryParse(stream.url);
      if (uri == null) return stream.copyWith(isFailed: true, failureReason: 'Invalid URL');

      final headers = Map<String, String>.from(stream.headers ?? {});
      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      }
      final isManifest = stream.url.contains('.m3u8') || stream.url.contains('.mpd');
      if (!isManifest) headers['Range'] = 'bytes=0-1024';

      final request = http.Request('GET', uri)..headers.addAll(headers);
      final streamedResponse = await httpClient.send(request).timeout(timeout);
      final status = streamedResponse.statusCode;
      final contentType = (streamedResponse.headers['content-type'] ?? '').toLowerCase();
      unawaited(streamedResponse.stream.drain().catchError((_) {}));

      if (status >= 400 && status != 416) {
        return stream.copyWith(isFailed: true, failureReason: 'HTTP $status');
      }
      if (contentType.contains('text/html')) {
        return stream.copyWith(isFailed: true, failureReason: 'HTML Challenge');
      }
      return stream;
    } on TimeoutException {
      // Do not count timeout as failed stream
      return stream;
    } on http.ClientException {
      return stream.copyWith(isFailed: true, failureReason: 'Connection Dropped');
    } on SocketException {
      return stream.copyWith(isFailed: true, failureReason: 'Connection Refused');
    } on HandshakeException {
      return stream.copyWith(isFailed: true, failureReason: 'SSL Error');
    } catch (_) {
      return stream;
    } finally {
      if (shouldClose) httpClient.close();
    }
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
        unawaited(streamedResponse.stream.drain().catchError((_) {}));
        return const StreamMetrics(
          ttfbMs: 9999,
          throughputMbPerSec: 0.0,
          estimatedBitrateMbPerSec: 0.0,
          headroomRatio: 0.0,
          isQualified: false,
          bytesTransferred: 0,
          explicitError: 'HTML Challenge',
        );
      }

      if (streamedResponse.statusCode >= 400 && streamedResponse.statusCode != 403 && streamedResponse.statusCode != 416) {
        unawaited(streamedResponse.stream.drain().catchError((_) {}));
        return StreamMetrics(
          ttfbMs: 9999,
          throughputMbPerSec: 0.0,
          estimatedBitrateMbPerSec: 0.0,
          headroomRatio: 0.0,
          isQualified: false,
          bytesTransferred: 0,
          explicitError: 'HTTP ${streamedResponse.statusCode}',
        );
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
    } on http.ClientException {
      return const StreamMetrics(
        ttfbMs: 9999,
        throughputMbPerSec: 0.0,
        estimatedBitrateMbPerSec: 0.0,
        headroomRatio: 0.0,
        isQualified: false,
        bytesTransferred: 0,
        explicitError: 'Connection Dropped',
      );
    } on SocketException {
      return const StreamMetrics(
        ttfbMs: 9999,
        throughputMbPerSec: 0.0,
        estimatedBitrateMbPerSec: 0.0,
        headroomRatio: 0.0,
        isQualified: false,
        bytesTransferred: 0,
        explicitError: 'Connection Refused',
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

  static int compareBySpeed(StreamSource a, StreamSource b) {
    final aSpeed = a.headroomRatio;
    final bSpeed = b.headroomRatio;

    if (aSpeed != null && bSpeed != null) {
      if (aSpeed != bSpeed) return bSpeed.compareTo(aSpeed);
    } else if (aSpeed != null && bSpeed == null) {
      return aSpeed > 0.0 ? -1 : 1;
    } else if (aSpeed == null && bSpeed != null) {
      return bSpeed > 0.0 ? 1 : -1;
    }

    final qCmp = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    if (qCmp != 0) return qCmp;

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
    void Function(ProbingStageEvent event)? onStageProgress,
  }) async {
    if (candidates.isEmpty) {
      throw ArgumentError('candidates list cannot be empty');
    }

    // Sort candidates by speed if known, then quality tier
    final sortedCandidates = List<StreamSource>.from(candidates)..sort(compareBySpeed);

    final totalCandidates = sortedCandidates.length;
    onProgress?.call('Stage 1/2: Health Gate (16 parallel)...', 0, 0);
    onStageProgress?.call(ProbingStageEvent(
      stage: 1,
      current: 0,
      total: totalCandidates,
      healthy: 0,
      message: 'Checking stream availability across providers...',
    ));

    // Stage 1: High-concurrency Health Gate (16 parallel, 900ms)
    final healthResults = <StreamSource>[];
    const healthConcurrency = 16;
    for (int i = 0; i < sortedCandidates.length; i += healthConcurrency) {
      final end = (i + healthConcurrency < sortedCandidates.length) ? i + healthConcurrency : sortedCandidates.length;
      final chunk = sortedCandidates.sublist(i, end);
      final results = await Future.wait(chunk.map((s) => checkStreamHealth(s, client: client)));
      healthResults.addAll(results);
      final healthyCount = healthResults.where((s) => !s.isFailed).length;
      final msg = 'Stage 1/2: Health check ($end/$totalCandidates streams, $healthyCount healthy)...';
      onProgress?.call(msg, end, 0);
      onStageProgress?.call(ProbingStageEvent(
        stage: 1,
        current: end,
        total: totalCandidates,
        healthy: healthyCount,
        message: msg,
      ));
    }

    final healthy = healthResults.where((s) => !s.isFailed).toList();
    final failed = healthResults.where((s) => s.isFailed).toList();

    final qualified = <StreamSource>[];
    final metricsMap = <String, StreamMetrics>{};
    final probedList = <StreamSource>[];
    int probedCount = 0;

    // Stage 2: Sliding Pool (concurrency 3) on healthy candidates
    final poolCandidates = List<StreamSource>.from(healthy.isNotEmpty ? healthy : sortedCandidates);
    final totalToProbe = poolCandidates.length < maxProbes ? poolCandidates.length : maxProbes;
    const poolConcurrency = 3;
    final activeProbes = <Future<void>>{};

    onStageProgress?.call(ProbingStageEvent(
      stage: 2,
      current: 0,
      total: totalToProbe,
      healthy: healthy.length,
      qualified: 0,
      message: 'Measuring stream throughput and headroom...',
    ));

    for (final stream in poolCandidates) {
      if (qualified.length >= targetQualified) break;

      late Future<void> probeTask;
      probeTask = () async {
        if (qualified.length >= targetQualified) return;
        final summary = '${stream.provider.toUpperCase()} ${stream.quality}';
        onProgress?.call('Stage 2/2: Probing speed ($summary, ${probedCount + 1}/$totalToProbe)...', probedCount + 1, qualified.length);

        final metrics = await probeStream(
          stream,
          runtimeMinutes: runtimeMinutes,
          client: client,
          timeout: perStreamTimeout,
        );
        probedCount++;

        if (metrics?.explicitError != null) {
          failed.add(stream.copyWith(isFailed: true, failureReason: metrics!.explicitError));
          return;
        }

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

        final isQual = metrics != null && metrics.isQualified;
        if (isQual && !qualified.any((q) => q.url == stream.url)) {
          qualified.add(enriched);
        }

        final msg = isQual
            ? 'Stage 2/2: Qualified ${stream.provider.toUpperCase()} ${stream.quality} (${headroom.toStringAsFixed(1)}x)'
            : 'Stage 2/2: Probing speed ($probedCount/$totalToProbe) - $summary';
        onProgress?.call(msg, probedCount, qualified.length);
        onStageProgress?.call(ProbingStageEvent(
          stage: 2,
          current: probedCount,
          total: totalToProbe,
          healthy: healthy.length,
          qualified: qualified.length,
          message: msg,
        ));
      }();

      activeProbes.add(probeTask);
      probeTask.whenComplete(() => activeProbes.remove(probeTask));

      if (activeProbes.length >= poolConcurrency) {
        await Future.any(activeProbes);
      }
    }

    if (activeProbes.isNotEmpty && qualified.length < targetQualified) {
      await Future.wait(activeProbes);
    }

    // 1. Probed streams with measured speed > 0, sorted strictly descending by speed
    final speedRankedProbed = probedList
        .where((s) => !failed.any((f) => f.url == s.url) && (s.headroomRatio ?? 0.0) > 0.0)
        .toList()
      ..sort(compareBySpeed);

    // 2. Unprobed healthy streams, sorted by quality
    final probedUrls = probedList.map((s) => s.url).toSet();
    final failedUrls = failed.map((f) => f.url).toSet();
    final unprobed = (healthy.isNotEmpty ? healthy : sortedCandidates)
        .where((s) => !probedUrls.contains(s.url) && !failedUrls.contains(s.url))
        .toList()
      ..sort(compareBySpeed);

    // 3. Stalled streams (probed but 0.0x throughput)
    final stalled = probedList
        .where((s) => !failed.any((f) => f.url == s.url) && (s.headroomRatio ?? 0.0) <= 0.0)
        .toList()
      ..sort(compareBySpeed);

    final allActive = [...speedRankedProbed, ...unprobed, ...stalled];
    final defaultCandidates = healthy.isNotEmpty ? healthy : sortedCandidates;
    final top = allActive.isNotEmpty ? allActive.first : defaultCandidates.first;
    final remainingActive = allActive.where((s) => s.url != top.url).toList();
    final fallbacks = remainingActive.take(2).toList();
    final unprobedRemaining = remainingActive.skip(fallbacks.length).toList();

    return RankedStreamResult(
      topStream: top,
      fallbackStreams: fallbacks,
      unprobedStreams: unprobedRemaining,
      failedStreams: failed,
      metrics: metricsMap,
      hasQualifiedStreams: speedRankedProbed.isNotEmpty,
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
