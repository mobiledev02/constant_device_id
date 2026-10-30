# Changelog

All notable changes to this package are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [0.2.0] — 2026-10-30

### Added
- Swift Package Manager (SwiftPM) support for iOS via `ios/constant_device_id/Package.swift`, aligning with modern Flutter iOS toolchains while retaining CocoaPods fallback compatibility via `.podspec`.
- In-memory caching for `ConstantDeviceId.getId()`: subsequent calls return instantly (~0 ms) without repeating platform channel round-trips or storage I/O.
- `ConstantDeviceId.cachedId` synchronous getter to access the cached ID without asynchronous awaiting once initialized.
- `ConstantDeviceId.clearCache()` to clear only the in-memory cache without modifying persistent storage.
- Optional `forceRefresh` parameter in `ConstantDeviceId.getId({bool forceRefresh = false})` to explicitly bypass the cache and re-query stores.
- In-flight request deduplication: concurrent calls to `getId()` coalesce into a single execution future, preventing redundant parallel platform channel calls and disk operations.
- Expanded unit test suite covering in-memory caching, in-flight deduplication, cache clearing, reset behavior, and all fallback layers.

### Changed
- Lowered minimum version constraints for all dependencies to maximize compatibility with consumer projects on older package versions:
  - `crypto: ^3.0.0` (allows any `3.x` version)
  - `flutter_secure_storage: ">=9.0.0 <12.0.0"` (supports `9.x`, `10.x`, and `11.x`)
  - `plugin_platform_interface: ^2.0.2` (allows any `2.x` version)
  - `shared_preferences: ^2.0.0` (allows any `2.x` version)
  - `uuid: ^4.0.0` (allows any `4.x` version)
  - `flutter_lints: ^3.0.0` in dev_dependencies
- Android native optimization: cached Widevine ID in memory (`@Volatile private var cachedWidevineId: String?`) to avoid repeated hardware `MediaDrm` allocations and driver calls.
- Parallelized persistent storage writes in Layer 3 (UUID generation) using `Future.wait`.
- Parallelized store deletion in `ConstantDeviceId.reset()`.
- Non-blocking Layer 2 promotion: writing the ID from `SharedPreferences` to `FlutterSecureStorage` now runs in the background (`unawaited`), reducing caller latency.

### Fixed
- Fixed `MissingPluginException` during testing and fallback execution by properly wrapping `SharedPreferences` calls in `try/catch` blocks and initializing mock storage in test suites.
- Ensured resilient fallback to Layer 3 (UUID generation) if `SharedPreferences` or `FlutterSecureStorage` fails or throws an exception.
- Fixed dependency alphabetical sorting in `example/pubspec.yaml`.


## [0.1.0] — 2026-03-16

### Added
- Initial release.
- `ConstantDeviceId.getId()` — returns a permanent, privacy-safe device identifier.
- `ConstantDeviceId.reset()` — clears locally stored ID from Secure Storage and SharedPreferences.
- **Layer 0 — Widevine DRM** (Android): hardware-bound ID that survives app uninstall and reinstall. SHA-256 hashed before use.
- **Layer 1 — Secure Storage / iOS Keychain**: encrypted storage that persists across reinstalls on iOS.
- **Layer 2 — SharedPreferences**: lightweight fallback with automatic promotion to secure storage.
- **Layer 3 — UUID v4 generation**: last-resort ID generated once and persisted to both stores.
- Android minimum SDK: 21 (Android 5.0 Lollipop).
- iOS minimum version: 12.0.
- Full unit-test suite with mock platform implementations.
- Example app demonstrating basic usage.
