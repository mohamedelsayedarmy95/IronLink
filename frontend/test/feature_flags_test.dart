import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironlink/core/api_client.dart';
import 'package:ironlink/core/crypto/secret_store.dart';
import 'package:ironlink/core/feature_flags.dart';

/// A flag system's failure mode is worse than the features it governs.
///
/// The obvious implementation — ask the server, treat "could not ask" as no —
/// means one unreachable endpoint disables messaging for everybody. These tests
/// exist mostly to hold the asymmetry that avoids it, and to hold the two
/// privacy properties that make a config service acceptable in this product at
/// all: it never learns who is asking, and the rollout bucket never leaves the
/// device.
void main() {
  ApiClient clientReturning(List<Map<String, dynamic>> flags) {
    final api = ApiClient();
    api.dio.httpClientAdapter = _StubAdapter(
      statusCode: 200,
      body: {'flags': flags},
    );
    return api;
  }

  ApiClient failingClient() {
    final api = ApiClient();
    api.dio.httpClientAdapter = _StubAdapter(throws: true);
    return api;
  }

  Map<String, dynamic> flag(
    String key, {
    String stage = 'general',
    bool killed = false,
    int percent = 100,
  }) =>
      {
        'key': key,
        'stage': stage,
        'killed': killed,
        'rollout_percent': percent,
      };

  group('what happens when the server cannot be reached', () {
    test('a shipped feature stays on', () async {
      // The property the whole design exists for. A config service being
      // unreachable is not a reason to withdraw something that already works,
      // and treating it as one would make this system a larger outage risk
      // than everything it governs.
      final store = MemorySecretStore();
      await store.write(
        'feature_flags_v1',
        jsonEncode([flag('messaging')]),
      );

      final flags = FeatureFlags(failingClient(), store: store, internalBuild: false);
      await flags.load();

      expect(flags.isEnabled('messaging'), isTrue);
      expect(flags.resolvedFromServer, isFalse);
    });

    test('an unreleased feature stays off', () async {
      final store = MemorySecretStore();
      await store.write(
        'feature_flags_v1',
        jsonEncode([flag('ironvault', stage: 'beta')]),
      );

      final flags = FeatureFlags(failingClient(), store: store, internalBuild: false);
      await flags.load();

      expect(flags.isEnabled('ironvault'), isFalse);
    });

    test('a killed feature stays killed', () async {
      // A kill is an incident response. Losing contact with the config service
      // afterwards must not quietly undo it.
      final store = MemorySecretStore();
      await store.write(
        'feature_flags_v1',
        jsonEncode([flag('attachments', killed: true)]),
      );

      final flags = FeatureFlags(failingClient(), store: store, internalBuild: false);
      await flags.load();

      expect(flags.isEnabled('attachments'), isFalse);
      expect(flags.fallbackFor('attachments'), isFalse);
    });

    test('a first install with no cache falls back to off for everything',
        () async {
      // Nothing is known, so nothing is claimed. This is the one case where a
      // shipped feature does read as off, and it cannot be avoided: with no
      // cache and no server there is no way to know the feature exists.
      final flags = FeatureFlags(failingClient(), store: MemorySecretStore(), internalBuild: false);
      await flags.load();

      expect(flags.isEnabled('messaging'), isFalse);
      expect(flags.all, isEmpty);
    });

    test('a corrupt cache is discarded rather than half-read', () async {
      final store = MemorySecretStore();
      await store.write('feature_flags_v1', 'not json at all');

      final flags = FeatureFlags(failingClient(), store: store, internalBuild: false);
      await flags.load();

      expect(flags.all, isEmpty);
    });
  });

  group('what the server says', () {
    test('a kill switch turns off a general feature', () async {
      final flags = FeatureFlags(
        clientReturning([flag('messaging', killed: true)]),
        store: MemorySecretStore(),
        internalBuild: false,
      );
      await flags.load();

      expect(flags.isEnabled('messaging'), isFalse);
      expect(flags.resolvedFromServer, isTrue);
    });

    test('an unknown key is off, not on', () async {
      // A typo must not be able to enable anything.
      final flags = FeatureFlags(
        clientReturning([flag('messaging')]),
        store: MemorySecretStore(),
        internalBuild: false,
      );
      await flags.load();

      expect(flags.isEnabled('ironcanvas'), isFalse);
    });

    test('a stage this build does not know is treated as off', () async {
      // A newer server inventing a stage must not enable anything on an older
      // client. Guessing in the other direction would ship an unreleased
      // feature to whoever had not updated.
      final flags = FeatureFlags(
        clientReturning([flag('something', stage: 'canary_wave_2')]),
        store: MemorySecretStore(),
        internalBuild: false,
      );
      await flags.load();

      expect(flags.isEnabled('something'), isFalse);
    });

    test('the response is cached for the next cold launch', () async {
      final store = MemorySecretStore();
      final first = FeatureFlags(
        clientReturning([flag('messaging')]),
        store: store,
        internalBuild: false,
      );
      await first.load();

      // Same storage, no server. A cold launch on a bad connection should
      // behave like the last good launch, not like a first install.
      final second = FeatureFlags(failingClient(), store: store, internalBuild: false);
      await second.load();

      expect(second.isEnabled('messaging'), isTrue);
    });
  });

  group('staged rollout, decided on this device', () {
    test('an install inside the share gets the feature', () async {
      final flags = FeatureFlags(
        clientReturning([flag('ai', stage: 'limited', percent: 50)]),
        store: MemorySecretStore(),
        seed: 10,
        internalBuild: false,
      );
      await flags.load();

      expect(flags.isEnabled('ai'), isTrue);
    });

    test('an install outside it does not', () async {
      final flags = FeatureFlags(
        clientReturning([flag('ai', stage: 'limited', percent: 50)]),
        store: MemorySecretStore(),
        seed: 90,
        internalBuild: false,
      );
      await flags.load();

      expect(flags.isEnabled('ai'), isFalse);
    });

    test('zero percent reaches nobody', () async {
      for (final seed in [0, 1, 50, 99]) {
        final flags = FeatureFlags(
          clientReturning([flag('ai', stage: 'limited', percent: 0)]),
          store: MemorySecretStore(),
          seed: seed,
          internalBuild: false,
        );
        await flags.load();
        expect(flags.isEnabled('ai'), isFalse, reason: 'seed $seed');
      }
    });

    test('the bucket survives a restart', () async {
      // This failed once, for a reason worth recording: the seed was written
      // with an escaped dollar sign, so it persisted as the literal text
      // "$generated", parsed back as null, and a fresh number was rolled on
      // every launch. A user would have drifted in and out of a staged feature
      // each time they opened the app — visible to them, invisible in any
      // metric, and impossible to reproduce on demand.
      final store = MemorySecretStore();
      final first = FeatureFlags(
        clientReturning([flag('ai', stage: 'limited', percent: 50)]),
        store: store,
        internalBuild: false,
      );
      await first.load();
      final before = first.isEnabled('ai');

      final buckets = <bool>{};
      for (var launch = 0; launch < 8; launch++) {
        final next = FeatureFlags(
          clientReturning([flag('ai', stage: 'limited', percent: 50)]),
          store: store,
        );
        await next.load();
        buckets.add(next.isEnabled('ai'));
      }

      expect(buckets, {before},
          reason: 'the same install must land in the same bucket every launch');
    });
  });

  group('what the server is never told', () {
    test('the flags request carries no identifier', () async {
      // The property that makes a config service acceptable here. If the
      // server decided who was in a rollout it would need to know who was
      // asking, and would accumulate a record of which users have which
      // features — a behavioural profile built by the config system.
      final api = ApiClient();
      final adapter = _StubAdapter(statusCode: 200, body: {'flags': []});
      api.dio.httpClientAdapter = adapter;

      await FeatureFlags(api, store: MemorySecretStore(), internalBuild: false).load();

      expect(adapter.lastOptions, isNotNull);
      final headers = adapter.lastOptions!.headers;
      expect(headers.containsKey('Authorization'), isFalse,
          reason: 'the endpoint is anonymous by design');
      expect(adapter.lastOptions!.uri.query, isEmpty,
          reason: 'no identifier may travel in the query string either');
    });

    test('the rollout seed is never sent', () async {
      final api = ApiClient();
      final adapter = _StubAdapter(statusCode: 200, body: {'flags': []});
      api.dio.httpClientAdapter = adapter;

      final flags = FeatureFlags(api, store: MemorySecretStore(), seed: 42, internalBuild: false);
      await flags.load();

      final sent = jsonEncode({
        'uri': adapter.lastOptions!.uri.toString(),
        'headers': adapter.lastOptions!.headers,
      });
      expect(sent.contains('42'), isFalse);
    });
  });
}

/// Answers every request with a fixed body, or throws.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.statusCode = 200, this.body, this.throws = false});

  final int statusCode;
  final Map<String, dynamic>? body;
  final bool throws;

  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    if (throws) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'no network',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body ?? const {}),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
