/// A Flutter plugin that provides a permanent device identifier.
///
/// The identifier persists across app reinstalls on Android (via Widevine DRM)
/// and on iOS (via the system Keychain).
///
/// ## Usage
///
/// ```dart
/// import 'package:constant_device_id/constant_device_id.dart';
///
/// final String id = await ConstantDeviceId.getId();
/// ```
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'src/constant_device_id_platform_interface.dart';

export 'src/constant_device_id_platform_interface.dart'
    show ConstantDeviceIdPlatform;

/// Provides a permanent device identifier that survives app reinstalls.
///
/// ### Resolution order
///
/// | Layer | Source                        | Survives reinstall          | Platform     |
/// |-------|-------------------------------|-----------------------------|--------------|
/// | 0     | Widevine DRM hardware ID      | Yes (until factory reset)   | Android only |
/// | 1     | Secure Storage / iOS Keychain | Yes (iOS) / No (Android)    | Both         |
/// | 2     | SharedPreferences             | No                          | Both         |
/// | 3     | Generated UUID v4             | No                          | Both         |
///
/// On Android, Layer 0 is almost always available, making the ID truly
/// permanent across installs. On iOS, the Keychain (Layer 1) natively
/// persists across reinstalls.
class ConstantDeviceId {
  ConstantDeviceId._();

  static const _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      /// The Keychain item is kept after the app is uninstalled on iOS.
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  @visibleForTesting
  static FlutterSecureStorage secureStorage = _defaultSecureStorage;

  static const _storageKey = 'constant_device_id_v1';

  static String? _cachedId;
  static Future<String>? _ongoingFetch;
  static int _epoch = 0;

  /// Returns the in-memory cached ID if available without making any async
  /// calls or platform channel queries, or `null` if [getId] has not resolved
  /// yet or if the cache was cleared.
  static String? get cachedId => _cachedId;

  /// Returns a permanent device identifier as a 64-character hex string (or UUID).
  ///
  /// The value is a SHA-256 hash of the underlying hardware identifier so that
  /// the raw hardware ID is never exposed or stored.
  ///
  /// This method is safe to call from any isolate and is idempotent — repeated
  /// calls return the same value as long as the hardware and storage are intact.
  ///
  /// Subsequent calls return the in-memory cached value immediately without
  /// performing platform channel calls or disk I/O, unless [forceRefresh] is `true`.
  /// Concurrent calls before the first call finishes are automatically deduplicated
  /// to share a single in-flight resolution.
  ///
  /// Throws only if all four layers fail simultaneously, which is an
  /// unrecoverable device state.
  static Future<String> getId({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedId != null) {
      return _cachedId!;
    }
    if (!forceRefresh && _ongoingFetch != null) {
      return _ongoingFetch!;
    }

    final currentEpoch = _epoch;
    final fetchFuture = _resolveId();
    _ongoingFetch = fetchFuture;

    try {
      final id = await fetchFuture;
      if (_epoch == currentEpoch) {
        _cachedId = id;
      }
      return id;
    } finally {
      if (identical(_ongoingFetch, fetchFuture)) {
        _ongoingFetch = null;
      }
    }
  }

  /// Clears only the in-memory cached device ID without modifying persistent storage.
  static void clearCache() {
    _epoch++;
    _cachedId = null;
    _ongoingFetch = null;
  }

  /// Clears the device ID from in-memory cache, Secure Storage, and SharedPreferences.
  ///
  /// The next call to [getId] on Android will still return the same
  /// hardware-derived ID because the Widevine layer is not affected.
  ///
  /// On iOS, clearing resets the stored ID; the next [getId] call generates
  /// and persists a new UUID.
  static Future<void> reset() async {
    _epoch++;
    _cachedId = null;
    _ongoingFetch = null;

    await Future.wait([
      secureStorage.delete(key: _storageKey).catchError((_) {}),
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_storageKey);
        } catch (_) {}
      }(),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Future<String> _resolveId() async {
    // Layer 0: Widevine DRM hardware ID (Android — survives uninstall/reinstall)
    final widevineId = await _getWidevineId();
    if (widevineId != null && widevineId.isNotEmpty) {
      return widevineId;
    }

    // Layer 1: Secure Storage (iOS Keychain survives reinstall natively)
    try {
      final secureId = await secureStorage.read(key: _storageKey);
      if (secureId != null && secureId.isNotEmpty) {
        return secureId;
      }
    } catch (_) {}

    // Layer 2: SharedPreferences fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefId = prefs.getString(_storageKey);
      if (prefId != null && prefId.isNotEmpty) {
        // Promote to secure storage for future reads asynchronously
        unawaited(
          secureStorage
              .write(key: _storageKey, value: prefId)
              .catchError((_) {}),
        );
        return prefId;
      }
    } catch (_) {}

    // Layer 3: Generate a new UUID and persist it in both stores concurrently
    final newId = const Uuid().v4();
    await Future.wait([
      secureStorage.write(key: _storageKey, value: newId).catchError((_) {}),
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_storageKey, newId);
        } catch (_) {}
      }(),
    ]);
    return newId;
  }

  static Future<String?> _getWidevineId() async {
    try {
      final rawId = await ConstantDeviceIdPlatform.instance.getWidevineId();
      if (rawId == null || rawId.isEmpty) return null;
      return _sha256(rawId);
    } catch (_) {
      return null;
    }
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
