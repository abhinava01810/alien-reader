import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Downloads the raw captured photo from the reader to a file on the phone.
///
/// Isolated on purpose: it only does a plain GET on the image URL the
/// existing capture call already returned, so the protected Pi service and
/// device classes are not touched.
class CaptureImageFetcher {
  CaptureImageFetcher({
    this._client,
    this.attemptTimeout = const Duration(seconds: 15),
    this.retryDelay = const Duration(milliseconds: 700),
    this.maxAttempts = 12,
  });

  final http.Client? _client;
  final Duration attemptTimeout;
  final Duration retryDelay;
  final int maxAttempts;

  /// Saves the image at [imageUrl] to [destination]. Retries while the
  /// reader still answers 404 (the photo may not be on disk the instant the
  /// capture call returns) or the network hiccups.
  Future<File> fetch(String imageUrl, File destination) async {
    final client = _client ?? http.Client();
    Object? lastError;
    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final res = await client
              .get(Uri.parse(imageUrl))
              .timeout(attemptTimeout);
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            await destination.parent.create(recursive: true);
            await destination.writeAsBytes(res.bodyBytes, flush: true);
            return destination;
          }
          lastError = 'HTTP ${res.statusCode}';
          if (res.statusCode != 404 && res.statusCode < 500) break;
        } on TimeoutException catch (e) {
          lastError = e;
        } on SocketException catch (e) {
          lastError = e;
        } on http.ClientException catch (e) {
          lastError = e;
        }
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      }
    } finally {
      if (_client == null) client.close();
    }
    throw CaptureImageException(
      'Could not get the photo from the reader ($lastError).',
    );
  }
}

class CaptureImageException implements Exception {
  const CaptureImageException(this.message);
  final String message;
  @override
  String toString() => message;
}
