import Flutter
import UIKit

/**
 * iOS implementation of the constant_device_id plugin.
 *
 * Widevine DRM is an Android-only technology and is not available on iOS.
 * Returning `nil` for `getWidevineId` causes the Dart layer to fall through
 * to Layer 1 (Keychain via flutter_secure_storage), which on iOS natively
 * persists across app reinstalls when `KeychainAccessibility.first_unlock`
 * is used — providing equivalent persistence behaviour.
 */
public class ConstantDeviceIdPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "constant_device_id",
            binaryMessenger: registrar.messenger()
        )
        let instance = ConstantDeviceIdPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getWidevineId":
            // Not available on iOS. The Dart layer falls back to the Keychain.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

