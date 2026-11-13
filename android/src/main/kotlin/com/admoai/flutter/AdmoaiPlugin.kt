package com.admoai.flutter

import android.content.Context
import android.app.UiModeManager
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.os.Build
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.DisplayMetrics
import android.view.Display
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Pure decision rules behind the signals, separated from Android framework
 * calls so they run in a plain JVM unit test.
 *
 * Parity table (identical rules are documented in the Dart test and in the
 * iOS plugin):
 *  - carrier: default-data subscription only; API >= 24; telephony feature
 *    required; anything else -> absent.
 *  - category: leanback / watch / automotive / pc feature, or a TELEVISION or
 *    WATCH UI mode -> "other" (never for CAR or DESK: a docked phone or
 *    tablet keeps its class); otherwise smallest full-display width < 600 dp
 *    -> "phone", >= 600 dp -> "tablet"; unreadable width -> absent. An
 *    unreadable UI mode is unknown, never "other". Identical to the native
 *    Android SDK. Hardware class computed once per process; display and
 *    carrier read per request.
 *  - iOS (for reference): carrier never; isiOSAppOnMac / Catalyst -> "other";
 *    idiom phone / pad / tv / carPlay / mac / vision.
 */
internal object DeviceSignalRules {
    const val INVALID_SUBSCRIPTION_ID = -1
    const val MIN_CARRIER_SDK = 24
    const val TABLET_MIN_WIDTH_DP = 600f

    val OTHER_FEATURES = setOf(
        "android.software.leanback",
        "android.hardware.type.watch",
        "android.hardware.type.automotive",
        "android.hardware.type.pc",
    )

    val OTHER_UI_MODES = setOf(
        Configuration.UI_MODE_TYPE_TELEVISION,
        Configuration.UI_MODE_TYPE_WATCH,
    )

    fun classify(features: Set<String>, uiModeType: Int?, smallestWidthDp: Float?): String? {
        if (features.any { it in OTHER_FEATURES }) return "other"
        if (uiModeType != null && uiModeType in OTHER_UI_MODES) return "other"
        val sw = smallestWidthDp ?: return null
        return if (sw >= TABLET_MIN_WIDTH_DP) "tablet" else "phone"
    }

    /** True when the carrier name may be read for this subscription. */
    fun normalizeSubscription(subId: Int, sdkInt: Int, hasTelephony: Boolean): Boolean =
        sdkInt >= MIN_CARRIER_SDK && hasTelephony && subId != INVALID_SUBSCRIPTION_ID
}

/**
 * Process-wide cache of the hardware-class answer ("is this a TV, watch,
 * automotive or PC device?"). Those inputs never change while the process
 * lives, so the probe runs once. A probe that throws caches nothing (it is
 * retried on the next read) and counts as "not other" for that call.
 */
internal class HardwareClassCache {
    @Volatile private var cachedIsOther: Boolean? = null

    fun isOther(probe: () -> Boolean): Boolean {
        cachedIsOther?.let { return it }
        return try {
            probe().also { cachedIsOther = it }
        } catch (_: Throwable) {
            false
        }
    }
}

/**
 * Category for one read: the cached hardware class decides "other"; otherwise
 * the display width is read now (every call) and classified.
 */
internal fun readCategoryWith(
    hardware: HardwareClassCache,
    hardwareProbe: () -> Boolean,
    widthProvider: () -> Float?,
): String? =
    if (hardware.isOther(hardwareProbe)) "other"
    else DeviceSignalRules.classify(emptySet(), null, widthProvider())

/**
 * Exposes coarse device signals to the Dart SDK over `admoai/device_signals`.
 *
 * Only the application context is retained (never an Activity). Every failure
 * is swallowed: a signal that cannot be read is simply absent from the result.
 */
class AdmoaiPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "collect") {
            result.notImplemented()
            return
        }
        val out = HashMap<String, String>()
        val ctx = appContext
        if (ctx != null) {
            readCarrier(ctx)?.let { out["carrier"] = it }
            readCategory(ctx)?.let { out["category"] = it }
        }
        result.success(out)
    }

    private fun readCarrier(ctx: Context): String? {
        return try {
            if (Build.VERSION.SDK_INT < DeviceSignalRules.MIN_CARRIER_SDK) return null
            val hasTelephony =
                ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
            val subId = SubscriptionManager.getDefaultDataSubscriptionId()
            if (!DeviceSignalRules.normalizeSubscription(subId, Build.VERSION.SDK_INT, hasTelephony)) {
                return null
            }
            val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                ?: return null
            tm.createForSubscriptionId(subId).networkOperatorName?.takeIf { it.isNotBlank() }
        } catch (_: Throwable) {
            null
        }
    }

    private fun readCategory(ctx: Context): String? {
        return try {
            readCategoryWith(hardwareClass, { probeHardwareIsOther(ctx) }, { fullDisplaySmallestWidthDp(ctx) })
        } catch (_: Throwable) {
            null
        }
    }

    private fun probeHardwareIsOther(ctx: Context): Boolean {
        val pm = ctx.packageManager
        val features = DeviceSignalRules.OTHER_FEATURES.filter { pm.hasSystemFeature(it) }.toSet()
        return DeviceSignalRules.classify(features, readUiModeType(ctx), 0f) == "other"
    }

    /** Current UI mode type, or null when it cannot be read (unknown, not "other"). */
    private fun readUiModeType(ctx: Context): Int? {
        return try {
            (ctx.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * Smallest width of the physical default display in dp. Independent of the
     * app window (split-screen, freeform) and of rotation. The Display comes
     * from DisplayManager, so no non-visual-context StrictMode violation is
     * raised on API 30+ (unlike Context.getDisplay() / WindowManager from an
     * application context). Display.getRealMetrics is deprecated since API 31
     * but remains the only dependency-free full-display read on API 19-35.
     */
    @Suppress("DEPRECATION")
    private fun fullDisplaySmallestWidthDp(ctx: Context): Float? {
        val dm = ctx.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager ?: return null
        val display = dm.getDisplay(Display.DEFAULT_DISPLAY) ?: return null
        val metrics = DisplayMetrics()
        display.getRealMetrics(metrics)
        if (metrics.density <= 0f) return null
        return minOf(metrics.widthPixels, metrics.heightPixels) / metrics.density
    }

    companion object {
        private const val CHANNEL = "admoai/device_signals"
        private val hardwareClass = HardwareClassCache()
    }
}
