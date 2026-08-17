import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'bloc/alert_bloc.dart';
import 'domain/processing_job.dart';
import 'keyword_alert_pipeline.dart';
import 'local/alert_store.dart';
import 'ocr/extractor_factory.dart';

/// The single place a decrypted document is handed to the pipeline.
///
/// WHY THE WIDGET DOES NOT CALL THE PIPELINE DIRECTLY
///
/// The bytes become available inside an image widget, which is the wrong
/// place to start work from. A chat with twenty photographs builds and rebuilds
/// those widgets constantly as the list scrolls, and each rebuild would launch
/// another extraction — twenty concurrent OCR jobs on a phone is not a feature,
/// it is a thermal event. §8.2 is explicit that there is no permanent OCR
/// daemon and that a document is processed only once per processing version.
///
/// So this sits between them and enforces three things the widget cannot:
///
/// * **One at a time.** Extraction is serialized. Scrolling past ten images
///   queues ten documents; it does not run ten engines.
/// * **Once per document.** An in-flight and recently-finished set stops the
///   same attachment being enqueued again by the next rebuild, before the
///   store's own idempotency check is even consulted.
/// * **Only what is worth reading.** Messages the user sent themselves, and
///   secret chats, never enter the queue at all.
class KeywordAlertService {
  KeywordAlertService({
    required AlertStore store,
    required AlertBloc bloc,
    KeywordAlertPipeline? pipeline,
    this.maxQueueDepth = 32,
  })  : _store = store,
        _bloc = bloc,
        _pipeline = pipeline ??
            KeywordAlertPipeline(
              store: store,
              extractors: KeywordExtractors.forPlatform(),
            );

  final AlertStore _store;
  final AlertBloc _bloc;
  final KeywordAlertPipeline _pipeline;

  /// A ceiling on how far behind the queue may fall.
  ///
  /// Scrolling fast through a long gallery can outrun extraction badly. Beyond
  /// this the oldest waiting document is dropped rather than the newest
  /// refused: the one the user just scrolled to is the one they are looking
  /// at, and a queue that grows without limit is a memory leak holding
  /// decrypted documents.
  final int maxQueueDepth;

  final Queue<_ScanRequest> _queue = Queue();
  final Set<String> _seen = {};
  bool _draining = false;

  /// Offers a decrypted document for checking.
  ///
  /// Returns immediately. Never throws: a failure to check a document must not
  /// take down the screen that was merely trying to display it.
  void offer({
    required Uint8List bytes,
    required String conversationId,
    required String messageId,
    required String attachmentId,
    required String recipientUserId,
    String? mimeType,
    bool isMine = false,
    bool isSecret = false,
  }) {
    // A document the user sent themselves does not need to be brought to
    // their attention — they chose its contents.
    if (isMine) return;

    // Secret chats are never written to any store on this device, and an
    // alert about one would outlive the message it describes by 48 hours.
    // The same rule the message cache already follows.
    if (isSecret) return;

    final key = '$conversationId|$messageId|$attachmentId';
    if (!_seen.add(key)) return;

    _queue.add(_ScanRequest(
      bytes: bytes,
      conversationId: conversationId,
      messageId: messageId,
      attachmentId: attachmentId,
      recipientUserId: recipientUserId,
      mimeType: mimeType,
    ));

    while (_queue.length > maxQueueDepth) {
      final dropped = _queue.removeFirst();
      // Forgotten rather than remembered as done, so it can be offered again
      // when the user scrolls back to it.
      _seen.remove(
        '${dropped.conversationId}|${dropped.messageId}|${dropped.attachmentId}',
      );
    }

    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final request = _queue.removeFirst();
        await _run(request);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _run(_ScanRequest request) async {
    try {
      final outcome = await _pipeline.process(
        bytes: request.bytes,
        conversationId: request.conversationId,
        messageId: request.messageId,
        attachmentId: request.attachmentId,
        recipientUserId: request.recipientUserId,
        declaredMimeType: request.mimeType,
      );

      if (outcome.alerts.isNotEmpty) {
        // The pipeline has already written them; this only asks the bloc to
        // re-read, so a duplicate notification cannot create a duplicate row.
        _bloc.add(AlertsRaised(outcome.alerts));
      }

      // A document that could not be read this time may be readable next time
      // — a transient decode failure, or an engine that was not ready. Letting
      // it be offered again is the bounded retry §8.4 asks for, driven by the
      // user looking at it rather than by a timer.
      if (outcome.job.status == JobStatus.failed ||
          outcome.job.status == JobStatus.waitingForNetwork ||
          outcome.job.status == JobStatus.ocrUnavailable) {
        _seen.remove(
          '${request.conversationId}|${request.messageId}|${request.attachmentId}',
        );
      }
    } catch (e) {
      // Nothing here is important enough to break the chat over.
      debugPrint('[keyword-alert] scan failed: $e');
      _seen.remove(
        '${request.conversationId}|${request.messageId}|${request.attachmentId}',
      );
    }
  }

  /// Clears what this session remembers having checked.
  ///
  /// Called on sign-out alongside the store. The store is wiped there; this
  /// set would otherwise keep claiming documents were already handled for a
  /// user who is no longer signed in.
  void reset() {
    _queue.clear();
    _seen.clear();
  }

  @visibleForTesting
  int get queueDepth => _queue.length;

  @visibleForTesting
  bool get isIdle => !_draining && _queue.isEmpty;

  @visibleForTesting
  AlertStore get store => _store;
}

class _ScanRequest {
  const _ScanRequest({
    required this.bytes,
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.recipientUserId,
    this.mimeType,
  });

  final Uint8List bytes;
  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String recipientUserId;
  final String? mimeType;
}

/// What a display widget needs to know to offer what it just decrypted.
///
/// Passed as one object rather than five loose parameters so that a call site
/// which forgets a field fails to compile instead of silently attributing an
/// alert to the wrong conversation.
class KeywordScanContext {
  const KeywordScanContext({
    required this.service,
    required this.conversationId,
    required this.messageId,
    required this.attachmentId,
    required this.recipientUserId,
    this.isMine = false,
    this.isSecret = false,
    this.mimeType,
  });

  final KeywordAlertService service;
  final String conversationId;
  final String messageId;
  final String attachmentId;
  final String recipientUserId;
  final bool isMine;
  final bool isSecret;
  final String? mimeType;

  void offer(Uint8List bytes) => service.offer(
        bytes: bytes,
        conversationId: conversationId,
        messageId: messageId,
        attachmentId: attachmentId,
        recipientUserId: recipientUserId,
        mimeType: mimeType,
        isMine: isMine,
        isSecret: isSecret,
      );
}
