import 'stream_source.dart';

enum StreamProgressStatus {
  searching,
  resolved,
  error;

  static StreamProgressStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'searching':
        return StreamProgressStatus.searching;
      case 'resolved':
        return StreamProgressStatus.resolved;
      case 'error':
        return StreamProgressStatus.error;
      default:
        return StreamProgressStatus.resolved;
    }
  }
}

class StreamProgressEvent {
  final String provider;
  final StreamProgressStatus status;
  final int? count;
  final List<StreamSource>? streams;
  final bool isDone;
  final String? error;

  const StreamProgressEvent({
    required this.provider,
    required this.status,
    this.count,
    this.streams,
    this.isDone = false,
    this.error,
  });

  factory StreamProgressEvent.progress({
    required String provider,
    required StreamProgressStatus status,
    int? count,
  }) {
    return StreamProgressEvent(
      provider: provider,
      status: status,
      count: count,
      isDone: false,
    );
  }

  factory StreamProgressEvent.done(List<StreamSource> streams) {
    return StreamProgressEvent(
      provider: 'all',
      status: StreamProgressStatus.resolved,
      count: streams.length,
      streams: streams,
      isDone: true,
    );
  }

  factory StreamProgressEvent.error(String errorMessage) {
    return StreamProgressEvent(
      provider: 'all',
      status: StreamProgressStatus.error,
      error: errorMessage,
      isDone: true,
    );
  }
}
