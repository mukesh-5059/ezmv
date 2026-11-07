import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_core/shared_core.dart';

void main() {
  group('StreamRanker - Size and Bitrate Parsing', () {
    test('parseSizeBytes parses GB, GiB, MB, and MiB correctly', () {
      expect(StreamRanker.parseSizeBytes('Baththa.2026.1080p (8.93 GB)'), (8.93 * 1024 * 1024 * 1024).round());
      expect(StreamRanker.parseSizeBytes('Sample.720p 458 MB.mkv'), (458 * 1024 * 1024).round());
      expect(StreamRanker.parseSizeBytes('Movie 1.5 GiB'), (1.5 * 1024 * 1024 * 1024).round());
      expect(StreamRanker.parseSizeBytes('No size present'), isNull);
      expect(StreamRanker.parseSizeBytes(''), isNull);
      expect(StreamRanker.parseSizeBytes(null), isNull);
    });

    test('estimateBitrateMbPerSec calculates exact bitrate when sizeBytes is present', () {
      const stream = StreamSource(
        url: 'https://example.com/stream.mp4',
        quality: '1080p',
        provider: 'hdhub',
        sizeBytes: 9588514488,
      );
      // 9588514488 bytes / (1024*1024) = 9144.34 MB; runtime = 120 min (7200s); 9144.34 / 7200 = 1.27 MB/s
      final bitrate = StreamRanker.estimateBitrateMbPerSec(stream, runtimeMinutes: 120);
      expect(bitrate, closeTo(1.27, 0.05));
    });

    test('estimateBitrateMbPerSec parses size from filename when sizeBytes is null', () {
      const stream = StreamSource(
        url: 'https://example.com/stream.mp4',
        quality: '1080p',
        provider: 'plaviohd',
        filename: 'Movie.1080p.NF.DDP5.1 (8.93 GB)',
      );
      final bitrate = StreamRanker.estimateBitrateMbPerSec(stream, runtimeMinutes: 120);
      expect(bitrate, closeTo(1.27, 0.05));
    });

    test('estimateBitrateMbPerSec uses quality profiles when no size is available', () {
      const s1080 = StreamSource(url: 'https://a.com', quality: '1080p', provider: 'plaviohd');
      const s720 = StreamSource(url: 'https://b.com', quality: '720p', provider: 'plaviohd');
      const s480 = StreamSource(url: 'https://c.com', quality: '480p SD', provider: 'plaviohd');

      expect(StreamRanker.estimateBitrateMbPerSec(s1080), 0.75);
      expect(StreamRanker.estimateBitrateMbPerSec(s720), 0.35);
      expect(StreamRanker.estimateBitrateMbPerSec(s480), 0.15);
    });
  });

  group('StreamRanker - Stream Probing', () {
    test('probeStream returns qualified metrics for fast media stream', () async {
      final dummyBytes = List<int>.filled(262144, 1);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          dummyBytes,
          200,
          headers: {'content-type': 'video/mp4', 'content-length': '262144'},
        );
      });

      const stream = StreamSource(
        url: 'https://cdn.example.com/movie.mp4',
        quality: '720p',
        provider: 'plaviohd',
      );

      final metrics = await StreamRanker.probeStream(
        stream,
        client: mockClient,
        runtimeMinutes: 120,
      );

      expect(metrics, isNotNull);
      expect(metrics!.isQualified, isTrue);
      expect(metrics.bytesTransferred, greaterThanOrEqualTo(262144));
    });

    test('probeStream rejects HTML error pages', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '<html><body>Error 404 Not Found</body></html>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      const stream = StreamSource(url: 'https://cdn.example.com/stream', quality: '1080p', provider: 'hdhub');
      final metrics = await StreamRanker.probeStream(stream, client: mockClient);
      expect(metrics, isNull);
    });

    test('probeStream rejects 500 server errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      const stream = StreamSource(url: 'https://cdn.example.com/stream', quality: '1080p', provider: 'hdhub');
      final metrics = await StreamRanker.probeStream(stream, client: mockClient);
      expect(metrics, isNull);
    });
  });

  group('StreamRanker - Ranking & Fallback Management', () {
    test('rankStreams stops immediately after finding 3 qualified streams', () async {
      final dummyBytes = List<int>.filled(262144, 1);
      int probeCallCount = 0;

      final mockClient = MockClient((request) async {
        probeCallCount++;
        return http.Response.bytes(dummyBytes, 200, headers: {'content-type': 'video/mp4'});
      });

      final candidates = List.generate(
        8,
        (i) => StreamSource(url: 'https://example.com/s$i.mp4', quality: '1080p', provider: 'prov$i'),
      );

      final progressLogs = <String>[];
      final result = await StreamRanker.rankStreams(
        candidates,
        client: mockClient,
        targetQualified: 3,
        maxProbes: 6,
        onProgress: (msg, probed, qual) => progressLogs.add('$probed: $msg'),
      );

      expect(probeCallCount, 3);
      expect(result.topStream.url, 'https://example.com/s0.mp4');
      expect(result.fallbackStreams.length, 2);
      expect(result.unprobedStreams.length, 5);
      expect(result.hasQualifiedStreams, isTrue);
      expect(progressLogs.isNotEmpty, isTrue);
    });

    test('rankStreams degrades gracefully when no stream achieves headroom requirement', () async {
      // Simulate low throughput by returning minimal bytes
      final tinyBytes = List<int>.filled(512, 1);
      final mockClient = MockClient((request) async {
        return http.Response.bytes(tinyBytes, 200, headers: {'content-type': 'video/mp4'});
      });

      final candidates = [
        const StreamSource(url: 'https://example.com/s0.mp4', quality: '1080p', provider: 'p0'),
        const StreamSource(url: 'https://example.com/s1.mp4', quality: '720p', provider: 'p1'),
      ];

      final result = await StreamRanker.rankStreams(
        candidates,
        client: mockClient,
        maxProbes: 2,
      );

      expect(result.hasQualifiedStreams, isFalse);
      expect(result.topStream, isNotNull);
      expect(result.fallbackStreams.length, 1);
    });

    test('findNextFallback locates the first qualified stream from unprobed pool', () async {
      final dummyBytes = List<int>.filled(262144, 1);
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('dead')) {
          return http.Response('error', 500);
        }
        return http.Response.bytes(dummyBytes, 200, headers: {'content-type': 'video/mp4'});
      });

      final unprobed = [
        const StreamSource(url: 'https://example.com/dead.mp4', quality: '1080p', provider: 'p0'),
        const StreamSource(url: 'https://example.com/alive.mp4', quality: '720p', provider: 'p1'),
      ];

      final fallback = await StreamRanker.findNextFallback(unprobed, client: mockClient);
      expect(fallback, isNotNull);
      expect(fallback!.url, 'https://example.com/alive.mp4');
    });

    test('checkInternetReachability returns true on 204 and false on error', () async {
      final goodClient = MockClient((_) async => http.Response('', 204));
      expect(await StreamRanker.checkInternetReachability(client: goodClient), isTrue);

      final badClient = MockClient((_) async => throw Exception('Socket connection failed'));
      expect(await StreamRanker.checkInternetReachability(client: badClient), isFalse);
    });
  });
}
