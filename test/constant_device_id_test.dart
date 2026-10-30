import 'package:constant_device_id/constant_device_id.dart';
import 'package:constant_device_id/src/constant_device_id_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Mock platforms
// ---------------------------------------------------------------------------
class _MockWithWidevine extends ConstantDeviceIdPlatform {
  int callCount = 0;

  @override
  Future<String?> getWidevineId() async {
    callCount++;
    return 'mock-widevine-base64-id';
  }
}

class _MockWithoutWidevine extends ConstantDeviceIdPlatform {
  @override
  Future<String?> getWidevineId() async => null;
}

class _MockThrowingWidevine extends ConstantDeviceIdPlatform {
  @override
  Future<String?> getWidevineId() async =>
      throw PlatformException(code: 'DRM_ERROR', message: 'DRM unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ConstantDeviceId.clearCache();
  });

  tearDown(() {
    ConstantDeviceId.clearCache();
  });

  group('ConstantDeviceIdPlatform', () {
    test('default instance is MethodChannelConstantDeviceId', () {
      expect(
        ConstantDeviceIdPlatform.instance,
        isA<MethodChannelConstantDeviceId>(),
      );
    });

    test('MethodChannelConstantDeviceId invokes getWidevineId', () async {
      final platform = MethodChannelConstantDeviceId();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        platform.methodChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'getWidevineId') {
            return 'native-drm-id';
          }
          return null;
        },
      );

      final id = await platform.getWidevineId();
      expect(id, equals('native-drm-id'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });
  });

  group('ConstantDeviceId.getId() — with Widevine', () {
    late _MockWithWidevine mock;

    setUp(() {
      mock = _MockWithWidevine();
      ConstantDeviceIdPlatform.instance = mock;
    });

    test('returns a non-empty string', () async {
      final id = await ConstantDeviceId.getId();
      expect(id, isNotEmpty);
    });

    test('returns a 64-character lowercase hex string (SHA-256)', () async {
      final id = await ConstantDeviceId.getId();
      expect(id.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(id), isTrue);
    });

    test('is deterministic — same Widevine input yields same output', () async {
      final id1 = await ConstantDeviceId.getId();
      final id2 = await ConstantDeviceId.getId();
      expect(id1, equals(id2));
    });
  });

  group('ConstantDeviceId.getId() — without Widevine (fallback layers)', () {
    setUp(() {
      ConstantDeviceIdPlatform.instance = _MockWithoutWidevine();
    });

    test('still returns a non-empty string via fallback', () async {
      final id = await ConstantDeviceId.getId();
      expect(id, isNotEmpty);
    });

    test('Layer 1: returns ID from Secure Storage if already saved', () async {
      FlutterSecureStorage.setMockInitialValues({
        'constant_device_id_v1': 'existing-secure-id',
      });

      final id = await ConstantDeviceId.getId();
      expect(id, equals('existing-secure-id'));
    });

    test(
        'Layer 2: falls back to SharedPreferences and promotes to Secure Storage',
        () async {
      SharedPreferences.setMockInitialValues({
        'constant_device_id_v1': 'existing-pref-id',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final id = await ConstantDeviceId.getId();
      expect(id, equals('existing-pref-id'));

      // Wait a tick for promotion write to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final promoted = await ConstantDeviceId.secureStorage.read(
        key: 'constant_device_id_v1',
      );
      expect(promoted, equals('existing-pref-id'));
    });

    test(
        'Layer 3: generates UUID and persists to both stores when stores are empty',
        () async {
      final id = await ConstantDeviceId.getId();
      expect(id, isNotEmpty);

      // Verify UUID v4 format
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      expect(uuidRegex.hasMatch(id), isTrue);

      final secureId = await ConstantDeviceId.secureStorage.read(
        key: 'constant_device_id_v1',
      );
      expect(secureId, equals(id));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('constant_device_id_v1'), equals(id));
    });

    test('handles PlatformException from Widevine and uses fallback', () async {
      ConstantDeviceIdPlatform.instance = _MockThrowingWidevine();

      final id = await ConstantDeviceId.getId();
      expect(id, isNotEmpty);
    });
  });

  group('Performance & In-Memory Caching', () {
    test('subsequent calls return cached ID without invoking platform again',
        () async {
      final mock = _MockWithWidevine();
      ConstantDeviceIdPlatform.instance = mock;

      expect(mock.callCount, 0);
      expect(ConstantDeviceId.cachedId, isNull);

      final id1 = await ConstantDeviceId.getId();
      expect(mock.callCount, 1);
      expect(ConstantDeviceId.cachedId, equals(id1));

      final id2 = await ConstantDeviceId.getId();
      expect(id2, equals(id1));
      expect(mock.callCount, 1); // No additional call to platform
    });

    test('forceRefresh bypasses in-memory cache and re-queries', () async {
      final mock = _MockWithWidevine();
      ConstantDeviceIdPlatform.instance = mock;

      final id1 = await ConstantDeviceId.getId();
      expect(mock.callCount, 1);

      final id2 = await ConstantDeviceId.getId(forceRefresh: true);
      expect(id2, equals(id1));
      expect(mock.callCount, 2);
    });

    test('deduplicates concurrent calls into a single resolution', () async {
      final mock = _MockWithWidevine();
      ConstantDeviceIdPlatform.instance = mock;

      // Launch 5 concurrent calls
      final results = await Future.wait([
        ConstantDeviceId.getId(),
        ConstantDeviceId.getId(),
        ConstantDeviceId.getId(),
        ConstantDeviceId.getId(),
        ConstantDeviceId.getId(),
      ]);

      expect(mock.callCount, 1); // Only 1 platform call despite 5 requests
      for (final id in results) {
        expect(id, equals(results.first));
      }
    });

    test('clearCache clears in-memory cache while preserving stored data',
        () async {
      ConstantDeviceIdPlatform.instance = _MockWithoutWidevine();
      FlutterSecureStorage.setMockInitialValues({
        'constant_device_id_v1': 'persisted-id',
      });

      final id = await ConstantDeviceId.getId();
      expect(id, equals('persisted-id'));
      expect(ConstantDeviceId.cachedId, equals('persisted-id'));

      ConstantDeviceId.clearCache();
      expect(ConstantDeviceId.cachedId, isNull);

      // Re-fetching retrieves the persisted ID from storage
      final idAfterClear = await ConstantDeviceId.getId();
      expect(idAfterClear, equals('persisted-id'));
    });

    test('reset clears cache, Secure Storage, and SharedPreferences', () async {
      ConstantDeviceIdPlatform.instance = _MockWithoutWidevine();
      final id1 = await ConstantDeviceId.getId();
      expect(id1, isNotEmpty);
      expect(ConstantDeviceId.cachedId, equals(id1));

      await ConstantDeviceId.reset();
      expect(ConstantDeviceId.cachedId, isNull);

      final secureId = await ConstantDeviceId.secureStorage.read(
        key: 'constant_device_id_v1',
      );
      expect(secureId, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('constant_device_id_v1'), isNull);

      // Next getId() generates a fresh UUID
      final id2 = await ConstantDeviceId.getId();
      expect(id2, isNot(equals(id1)));
    });
  });
}
