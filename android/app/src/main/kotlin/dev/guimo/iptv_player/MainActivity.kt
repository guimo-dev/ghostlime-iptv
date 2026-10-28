package dev.guimo.iptv_player

import android.app.UiModeManager
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The app's only activity; it also serves the window brightness and device channels. */
class MainActivity : FlutterActivity() {
    /**
     * Turns off Android's own focus highlight (API 26+) on the window's views:
     * on Android 8-9 boxes driven with a D-pad (Fire OS 7, Android TV 9) the
     * first key left touch mode and framed the whole Flutter view in the
     * system's accent colour. Flutter draws its own focus.
     */
    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            disableFocusHighlight(window.decorView)
        }
    }

    /** Disables the default focus highlight on [view] and its descendants. */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun disableFocusHighlight(view: View) {
        view.defaultFocusHighlightEnabled = false
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                disableFocusHighlight(view.getChildAt(index))
            }
        }
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTv())
                    else -> result.notImplemented()
                }
            }
    }

    /** Whether this device is a TV: Android TV, Google TV or Fire TV. */
    private fun isTv(): Boolean {
        val uiMode = getSystemService(UI_MODE_SERVICE) as UiModeManager
        return uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature("android.software.leanback") ||
            packageManager.hasSystemFeature("amazon.hardware.fire_tv")
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
        const val DEVICE_CHANNEL = "ghostlime/device"

        /** Lowest brightness set, so the screen never goes fully dark. */
        const val MIN_BRIGHTNESS = 0.01f
    }
}
