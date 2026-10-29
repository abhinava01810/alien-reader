import 'cloud_api_service.dart';

/// One usage record (`UsageOut`). Counts and timings only; no document
/// text, images, summaries or audio ever leave the phone or reader.
class UsageRecord {
  const UsageRecord({
    required this.id,
    required this.deviceId,
    required this.wordCount,
    required this.inputTokens,
    required this.outputTokens,
    required this.processingMs,
    required this.summaryUsed,
    required this.createdAt,
  });

  factory UsageRecord.fromJson(Map<String, dynamic> json) => UsageRecord(
    id: (json['id'] as num).toInt(),
    deviceId: (json['device_id'] as num?)?.toInt(),
    wordCount: (json['word_count'] as num).toInt(),
    inputTokens: (json['input_tokens'] as num).toInt(),
    outputTokens: (json['output_tokens'] as num).toInt(),
    processingMs: (json['processing_ms'] as num?)?.toInt(),
    summaryUsed: json['summary_used'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
  );

  final int id;
  final int? deviceId;
  final int wordCount;
  final int inputTokens;
  final int outputTokens;
  final int? processingMs;
  final bool summaryUsed;
  final DateTime? createdAt;
}

/// Privacy-preserving usage metadata against the Naadh cloud API.
class UsageCloudService {
  UsageCloudService({CloudApiService? api})
    : _api = api ?? CloudApiService.instance;

  final CloudApiService _api;

  Future<UsageRecord> logUsage({
    int? deviceId,
    required int wordCount,
    required int inputTokens,
    required int outputTokens,
    int? processingMs,
    required bool summaryUsed,
  }) async {
    final body = await _api.post(
      '/usage',
      json: {
        'device_id': deviceId,
        'word_count': wordCount,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'processing_ms': processingMs,
        'summary_used': summaryUsed,
      },
      auth: true,
    );
    return UsageRecord.fromJson(body as Map<String, dynamic>);
  }

  Future<List<UsageRecord>> getUsageHistory() async {
    final body = await _api.get('/usage') as List<dynamic>;
    return body
        .map((e) => UsageRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
