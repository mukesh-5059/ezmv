class StreamSource {
  final String url;
  final String quality;
  final String? filename;
  final int? sizeBytes;
  final String? formattedSize;
  final int? priority;
  final String provider;
  final String? host;
  final List<String> languages;
  final Map<String, String>? headers;
  final double? headroomRatio;

  const StreamSource({
    required this.url,
    required this.quality,
    this.filename,
    this.sizeBytes,
    this.formattedSize,
    this.priority,
    required this.provider,
    this.host,
    this.languages = const [],
    this.headers,
    this.headroomRatio,
  });

  StreamSource copyWith({
    String? url,
    String? quality,
    String? filename,
    int? sizeBytes,
    String? formattedSize,
    int? priority,
    String? provider,
    String? host,
    List<String>? languages,
    Map<String, String>? headers,
    double? headroomRatio,
  }) {
    return StreamSource(
      url: url ?? this.url,
      quality: quality ?? this.quality,
      filename: filename ?? this.filename,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      formattedSize: formattedSize ?? this.formattedSize,
      priority: priority ?? this.priority,
      provider: provider ?? this.provider,
      host: host ?? this.host,
      languages: languages ?? this.languages,
      headers: headers ?? this.headers,
      headroomRatio: headroomRatio ?? this.headroomRatio,
    );
  }

  factory StreamSource.fromJson(Map<String, dynamic> json) {
    final rawLanguages = json['languages'] as List? ?? [];
    Map<String, String>? parsedHeaders;
    if (json['headers'] is Map) {
      parsedHeaders = (json['headers'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    return StreamSource(
      url: json['url'] as String? ?? '',
      quality: json['quality'] as String? ?? '',
      filename: json['filename'] as String?,
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      formattedSize: json['formatted_size'] as String?,
      priority: (json['priority'] as num?)?.toInt(),
      provider: json['provider'] as String? ?? '',
      host: json['host'] as String?,
      languages: rawLanguages.map((l) => l.toString()).toList(),
      headers: parsedHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'quality': quality,
    'filename': filename,
    'size_bytes': sizeBytes,
    'formatted_size': formattedSize,
    'priority': priority,
    'provider': provider,
    'host': host,
    'languages': languages,
    'headers': headers,
  };
}
