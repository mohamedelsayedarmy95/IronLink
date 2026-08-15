import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'crypto/attachment_crypto.dart';

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
  MediaService(this._api, [AttachmentCrypto? crypto])
      : _crypto = crypto ?? AttachmentCrypto();

  final ApiClient _api;
  final AttachmentCrypto _crypto;

  /// What an encrypted body declares itself as, matching the server's
  /// ENCRYPTED_MIME_TYPE. The real type travels inside the envelope.
  static const encryptedMimeType = 'application/octet-stream';

  Future<Options> _auth() async {
    final token = await _api.accessToken;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  /// Encrypts [file] and uploads the ciphertext.
  ///
  /// Returns the key material, which the caller must place inside the Signal
  /// envelope. It is never sent to the server — doing so would make the
  /// stored object readable and defeat the entire exercise.
  Future<({UploadResult upload, AttachmentKey key})> uploadEncrypted(
    File file, {
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final plaintext = await file.readAsBytes();
    final material = _crypto.newKey(
      mimeType: mimeType,
      sizeBytes: plaintext.length,
    );
    final ciphertext = _crypto.encrypt(plaintext, material);

    final result = await _uploadBytes(
      ciphertext,
      filename: file.uri.pathSegments.last,
      // The server is told only that it holds opaque bytes. Declaring the
      // real type here would leak it from the storage metadata, and would
      // also send the object through image re-compression, which would
      // destroy the ciphertext.
      mimeType: encryptedMimeType,
      encrypted: true,
      onProgress: onProgress,
    );
    return (upload: result, key: material);
  }

  /// Downloads an encrypted attachment and returns its plaintext bytes.
  ///
  /// Throws [AttachmentTampered] if the authentication tag does not verify,
  /// which means the stored bytes are not what the sender produced.
  Future<Uint8List> downloadDecrypted(
    String mediaKey,
    AttachmentKey material,
  ) async {
    final url = await viewUrl(mediaKey);
    // A bare Dio instance: the presigned URL carries its own authorisation,
    // and attaching our bearer token to a request aimed at object storage
    // would hand the token to a third-party host.
    final res = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return _crypto.decrypt(
      Uint8List.fromList(res.data ?? const []),
      material,
    );
  }

  Future<UploadResult> upload(
    File file, {
    required String mimeType,
    String? resumeUploadId,
    void Function(double progress)? onProgress,
  }) async =>
      _uploadBytes(
        await file.readAsBytes(),
        filename: file.uri.pathSegments.last,
        mimeType: mimeType,
        encrypted: false,
        resumeUploadId: resumeUploadId,
        onProgress: onProgress,
      );

  Future<UploadResult> _uploadBytes(
    Uint8List bytes, {
    required String filename,
    required String mimeType,
    required bool encrypted,
    String? resumeUploadId,
    void Function(double progress)? onProgress,
  }) async {
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
          'filename': filename,
          'mime_type': mimeType,
          'total_size': bytes.length,
          'encrypted': encrypted,
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
