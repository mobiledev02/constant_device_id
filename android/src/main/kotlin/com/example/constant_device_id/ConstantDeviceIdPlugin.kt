package com.example.constant_device_id

import android.media.MediaDrm
import android.os.Build
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

/**
 * Android implementation of the constant_device_id plugin.
 *
 * Reads the Widevine DRM device unique ID — a hardware-bound identifier that
 * persists across app uninstalls and reinstalls. The raw bytes are returned as
 * a Base64 string; hashing for privacy is performed on the Dart side.
 */
class ConstantDeviceIdPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel

    companion object {
        /**
         * Well-known UUID for the Google Widevine DRM scheme.
         * Reference: https://dashif.org/identifiers/content_protection/
         */
        private val WIDEVINE_UUID = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)

        /**
         * Cache the Widevine ID at the process level to avoid redundant
         * expensive MediaDrm allocations and driver calls.
         */
        @Volatile
        private var cachedWidevineId: String? = null
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "constant_device_id")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getWidevineId" -> getWidevineId(result)
            else -> result.notImplemented()
        }
    }

    private fun getWidevineId(result: Result) {
        cachedWidevineId?.let {
            result.success(it)
            return
        }

        try {
            val drm = MediaDrm(WIDEVINE_UUID)
            val widevineId = drm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            val encoded = if (widevineId != null && widevineId.isNotEmpty()) {
                Base64.encodeToString(widevineId, Base64.NO_WRAP)
            } else {
                null
            }

            // MediaDrm.close() was added in API 28; use release() on older versions.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                drm.close()
            } else {
                @Suppress("DEPRECATION")
                drm.release()
            }

            if (encoded != null) {
                cachedWidevineId = encoded
            }
            result.success(encoded)
        } catch (e: Exception) {
            result.error("DRM_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
