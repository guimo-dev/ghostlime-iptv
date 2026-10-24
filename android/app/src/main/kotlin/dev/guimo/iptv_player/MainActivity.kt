package dev.guimo.iptv_player

import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The app's only activity; it also serves the window brightness channel. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BRIGHTNESS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(currentBrightness())
                    "set" -> {
                        val value = (call.arguments as? Number)?.toFloat()
                        if (value == null) {
                            result.error("bad_argument", "Expected a number", null)
                        } else {
                            setWindowBrightness(value.coerceIn(MIN_BRIGHTNESS, 1f))
                            result.success(null)
                        }
                    }
                    "reset" -> {
                        setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The window's brightness from 0 to 1: its own override when set,
     * otherwise the system setting (0 to 255).
     */
    private fun currentBrightness(): Double {
        val own = window.attributes.screenBrightness
        if (own >= 0f) return own.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (e: Settings.SettingNotFoundException) {
            0.5
        }
    }

    /** Sets the brightness of this window only (the system's is untouched). */
    private fun setWindowBrightness(value: Float) {
        val attributes = window.attributes
        attributes.screenBrightness = value
        window.attributes = attributes
    }

    private companion object {
        const val BRIGHTNESS_CHANNEL = "ghostlime/brightness"

        /** Lowest brightness set, so the screen never goes fully dark. */
        const val MIN_BRIGHTNESS = 0.01f
    }
}
