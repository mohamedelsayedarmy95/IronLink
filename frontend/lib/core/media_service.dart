import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';

class UploadResult {
  const UploadResult({
    required this.mediaKey,
    required this.mimeType,
    required this.sizeBytes,
    this.thumbnailKey,
  });

  final String mediaKey;
  final String mimeType;
  final int sizeBytes;
  final String? thumbnailKey;
}

/// Chunked, resumable upload client for /media/upload/*.
///
/// If the connection drops mid-upload, calling [upload] again with the same
/// [resumeUploadId] asks the server which chunks it already has and sends
/// only the missing ones.
class MediaService {
  MediaService(this._api);

  final ApiClient _api;

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<UploadResult> upload(
    File file, {
    required String mimeType,
    String? resumeUploadId,
    void Function(double progress)? onProgress,
  }) async {
    final bytes = await file.readAsBytes();
    final auth = await _auth();

    String uploadId;
    int chunkSize;
    int totalChunks;
    Set<int> alreadyUploaded = {};

    if (resumeUploadId != null) {
      // Resume: ask which chunks survived
      final status = await _api.dio.get<Map<String, dynamic>>(
        '/media/upload/$resumeUploadId',
        options: auth,
      );
      uploadId = resumeUploadId;
      totalChunks = status.data!['total_chunks'] as int;
      chunkSize = (bytes.length / totalChunks).ceil();
      alreadyUploaded = {
        for (final i in status.data!['received_chunks'] as List) i as int
      };
    } else {
      final init = await _api.dio.post<Map<String, dynamic>>(
        '/media/upload/init',
        data: {
          'filename': file.uri.pathSegments.last,
          'mime_type': mimeType,
          'total_size': bytes.length,
        },
        options: auth,
      );
      uploadId = init.data!['upload_id'] as String;
      chunkSize = init.data!['chunk_size'] as int;
      totalChunks = init.data!['total_chunks'] as int;
    }

    for (var i = 0; i < totalChunks; i++) {
      if (alreadyUploaded.contains(i)) continue;
      final start = i * chunkSize;
      final end = min(start + chunkSize, bytes.length);
      final chunk = Uint8List.sublistView(bytes, start, end);

      await _api.dio.put<void>(
        '/media/upload/$uploadId/chunk/$i',
        data: Stream.fromIterable([chunk]),
        options: Options(headers: {
          ...auth.headers!,
          Headers.contentLengthHeader: chunk.length,
          Headers.contentTypeHeader: 'application/octet-stream',
        }),
      );
      onProgress?.call((i + 1) / totalChunks);
    }

    final complete = await _api.dio.post<Map<String, dynamic>>(
      '/media/upload/$uploadId/complete',
      options: auth,
    );
    final d = complete.data!;
    return UploadResult(
      mediaKey: d['media_key'] as String,
      mimeType: d['mime_type'] as String,
      sizeBytes: d['size_bytes'] as int,
      thumbnailKey: d['thumbnail_key'] as String?,
    );
  }

  /// Fresh 5-minute view URL — generated per open, never cached long-term.
  Future<String> viewUrl(String mediaKey) async {
    final res = await _api.dio.get<Map<String, dynamic>>(
      '/media/$mediaKey/url',
      options: await _auth(),
    );
    return res.data!['url'] as String;
  }
}
