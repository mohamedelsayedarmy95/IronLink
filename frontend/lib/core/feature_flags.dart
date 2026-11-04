/// Runtime feature control — whether a shipped capability is currently on.
///
/// THE ASYMMETRY IS THE WHOLE DESIGN
///
/// The obvious implementation asks the server whether a feature is enabled and
/// treats "could not ask" as no. That turns the flag system into a larger
/// availability risk than everything it protects: one unreachable endpoint and
/// nobody can send a message.
///
/// So the fallback depends on the stage the feature had reached:
///
///   GENERAL and not killed  → stays ON when unresolvable
///   anything else           → stays OFF when unresolvable
///
/// A shipped feature is the status quo, and a config service being unreachable
/// is not a reason to withdraw it. An unreleased feature has never been on, and
/// an unreachable config service is certainly not a reason to start.
///
/// WHY THE ROLLOUT IS DECIDED HERE AND NOT ON THE SERVER
///
/// The server returns definitions, identical for everyone. This class decides
/// whether *this install* falls inside a percentage, using a random seed
/// generated once on first launch and never sent anywhere.
///
/// Had the server decided, it would need to know who was asking, and would
/// accumulate a record of which users have which features — a behavioural
/// profile produced by the configuration system, on a product built so the
/// server knows as little as possible. The cost is that per-user targeting is
/// impossible. A percentage does everything a staged release needs.
///
/// NOT A REPLACEMENT FOR `KeywordFeatureFlags`
///
/// That file holds compile-time flags for capabilities that are not finished,
/// and unfinished work *should* be compile-time — nobody should be able to
/// switch on a half-built feature from a server. This is the other half:
/// turning off something that is finished and shipped.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'crypto/secret_store.dart';

enum FeatureStage { off, internal, beta, limited, general }

@immutable
class FeatureFlag {
  const FeatureFlag({
    required this.key,
    required this.stage,
    required this.killed,
    required this.rolloutPercent,
  });

  final String key;
  final FeatureStage stage;
  final bool killed;
  final int rolloutPercent;

  /// What to assume when the server could not be reached.
  bool get fallback => stage == FeatureStage.general && !killed;

  factory FeatureFlag.fromJson(Map<String, dynamic> json) => FeatureFlag(
        key: json['key'] as String,
        stage: FeatureStage.values.firstWhere(
          (s) => s.name == json['stage'],
          // A stage this build does not know is one a newer server invented.
          // Treated as `off` rather than guessed at: an unknown stage must not
          // be able to enable anything.
          orElse: () => FeatureStage.off,
        ),
        killed: json['killed'] as bool? ?? false,
        rolloutPercent: (json['rollout_percent'] as num?)?.toInt() ?? 100,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'stage': stage.name,
        'killed': killed,
        'rollout_percent': rolloutPercent,
      };
}

class FeatureFlags {
  /// Persists through [SecretStore] rather than adding `shared_preferences`.
  ///
  /// Neither value stored here is a secret — a cache of public flag
  /// definitions and a random number between 0 and 99. But the interface is
  /// already in the project, already has an in-memory implementation for
  /// tests, and reaches the same platform storage. Adding a second key-value
  /// dependency for two non-secret values buys nothing and costs a package to
  /// keep patched, which §31.4 says has to be justified.
  FeatureFlags(
    this._api, {
    SecretStore? store,
    int? seed,
    bool? internalBuild,
  })  : _store = store ?? MemorySecretStore(),
        _seed = seed,
        _internalBuild = internalBuild ?? kDebugMode;

  final ApiClient _api;
  final SecretStore _store;
  int? _seed;

  /// Whether this build belongs to the internal channel.
  ///
  /// Defaults to `kDebugMode` because there is no separate internal
  /// distribution today, and a debug build is the closest honest equivalent.
  /// It is a parameter rather than a direct `kDebugMode` read for two reasons:
  /// the INTERNAL and BETA stages are otherwise untestable, since tests run in
  /// debug and would see every pre-release feature as on; and when a real
  /// internal channel exists, this becomes the one line that has to change.
  final bool _internalBuild;

  static const _cacheKey = 'feature_flags_v1';
  static const _seedKey = 'feature_rollout_seed_v1';

  Map<String, FeatureFlag> _flags = const {};

  /// Whether the definitions came from the server this session, as opposed to
  /// from cache or not at all. Surfaced so a settings screen can be honest
  /// about it rather than implying freshness it does not have.
  bool get resolvedFromServer => _resolvedFromServer;
  bool _resolvedFromServer = false;

  /// Loads the cache, then refreshes from the server.
  ///
  /// The cache is read first and used immediately, so a cold launch on a bad
  /// connection behaves like the last good launch rather than like a first
  /// install. A kill switch issued while the device was offline arrives with
  /// the refresh, seconds later.
  Future<void> load() async {
    await _primeSeed();
    await _readCache();
    await refresh();
  }

  Future<void> _readCache() async {
    final raw = await _store.read(_cacheKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _flags = {
        for (final json in list) json['key'] as String: FeatureFlag.fromJson(json)
      };
    } catch (err) {
      // A corrupt cache is discarded rather than repaired. Every flag then
      // falls back by stage, which is the same answer a first install gets.
      debugPrint('[features] discarding unreadable cache: $err');
      _flags = const {};
    }
  }

  Future<void> refresh() async {
    try {
      final res = await _api.dio.get<Map<String, dynamic>>('/features');
      final list = (res.data?['flags'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      _flags = {
        for (final json in list) json['key'] as String: FeatureFlag.fromJson(json)
      };
      _resolvedFromServer = true;
      await _store.write(_cacheKey, jsonEncode(list));
    } catch (err) {
      // Deliberately silent about the failure and deliberately not clearing
      // what is cached. Losing contact with the config service must not change
      // what is running.
      debugPrint('[features] refresh failed, keeping cached state: $err');
    }
  }

  /// A stable random number for this install, 0–99.
  ///
  /// Generated once and kept. Random rather than derived from a user or device
  /// identifier: a hash of an identifier would put the same person in the same
  /// bucket everywhere, which is a fingerprint. This is only ever compared
  /// against a percentage on this device and is never transmitted.
  int get _bucket {
    // Read synchronously from memory. `load()` primes it, so a rollout
    // decision never waits on storage while a widget is building — and a
    // missing seed generates one rather than blocking, because a feature
    // check must always be able to answer.
    final cached = _seed;
    if (cached != null) return cached;

    final generated = Random.secure().nextInt(100);
    _seed = generated;
    unawaited(_store.write(_seedKey, '$generated'));
    return generated;
  }

  Future<void> _primeSeed() async {
    if (_seed != null) return;
    final stored = await _store.read(_seedKey);
    final parsed = stored == null ? null : int.tryParse(stored);
    if (parsed != null && parsed >= 0 && parsed < 100) _seed = parsed;
  }

  /// Whether [key] is on for this install.
  ///
  /// An unknown key returns false. A capability the server has never heard of
  /// is one this build should not be running — and returning true would make a
  /// typo enable something.
  bool isEnabled(String key) {
    final flag = _flags[key];
    if (flag == null) return false;
    if (flag.killed) return false;

    return switch (flag.stage) {
      FeatureStage.off => false,
      // Both are pre-release channels; neither reaches a production build.
      FeatureStage.internal => _internalBuild,
      FeatureStage.beta => _internalBuild,
      FeatureStage.limited => _bucket < flag.rolloutPercent,
      FeatureStage.general => true,
    };
  }

  /// What [key] would be if the server could not be reached at all.
  ///
  /// Exposed so the asymmetry can be asserted directly by a test rather than
  /// inferred from behaviour.
  bool fallbackFor(String key) => _flags[key]?.fallback ?? false;

  /// Everything known, for the settings screen and for tests.
  Map<String, FeatureFlag> get all => Map.unmodifiable(_flags);
}
