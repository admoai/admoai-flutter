package com.admoai.flutter.leadform

import android.content.Context
import android.view.View
import android.view.ViewGroup
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** The secure views one engine owns, by the id Dart gave them. Main thread only. */
internal class LeadFormViews {
    private val views = HashMap<String, SecureFormWebView>()

    fun get(id: String): SecureFormWebView? = views[id]

    fun put(id: String, view: SecureFormWebView) {
        views.put(id, view)?.destroy()
    }

    fun remove(id: String) {
        views.remove(id)?.destroy()
    }

    fun clear() {
        val all = views.values.toList()
        views.clear()
        all.forEach { it.destroy() }
    }
}

/**
 * `admoai/lead_form`: the channel Dart drives the secure views with. Every failure is reported as a
 * code only; a URL, a message or a token never appears in an error.
 */
internal class LeadFormChannel(
    private val appContext: Context,
    messenger: BinaryMessenger,
    val views: LeadFormViews = LeadFormViews(),
    private val createView: (Context, String, (SurfaceEventKind, String?) -> Unit) -> SecureFormWebView =
        { context, url, onEvent -> SecureFormWebView(context, url, onEvent) },
    private val supported: (Context) -> Boolean = ::deviceHostsSecureView,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }

    fun detach() {
        channel.setMethodCallHandler(null)
        views.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(supported(appContext))
            "create" -> create(call, result)
            "post" -> {
                val id = call.argument<String>("id")
                val text = call.argument<String>("text")
                val view = id?.let { views.get(it) }
                if (view == null || text == null) {
                    result.error("no_view", null, null)
                } else {
                    view.send(text)
                    result.success(null)
                }
            }
            "destroy" -> {
                call.argument<String>("id")?.let { views.remove(it) }
                result.success(null)
            }
            else -> if (!FormTestHooks.handle(call, result, appContext, views)) result.notImplemented()
        }
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val url = call.argument<String>("url")
        if (id == null || url == null) {
            result.error("bad_arguments", null, null)
            return
        }
        try {
            val view = createView(appContext, url) { kind, text -> emit(id, kind, text) }
            views.put(id, view)
            view.load()
            result.success(null)
        } catch (e: Throwable) {
            // The type only: never the URL.
            result.error("create_failed", e.javaClass.simpleName, null)
        }
    }

    private fun emit(id: String, kind: SurfaceEventKind, text: String?) {
        val args = HashMap<String, String>()
        args["id"] = id
        args["kind"] = kind.wire
        if (text != null) args["text"] = text
        channel.invokeMethod("event", args)
    }

    companion object {
        const val CHANNEL = "admoai/lead_form"
    }
}

/** True when the device has a WebView provider that can listen to messages from one origin. */
internal fun deviceHostsSecureView(context: Context): Boolean = try {
    WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) &&
        (android.os.Build.VERSION.SDK_INT < 26 || WebViewCompat.getCurrentWebViewPackage(context) != null)
} catch (_: Throwable) {
    false
}

/**
 * The platform view factory: hands out the view the controller created for `{id}` and never creates
 * one. A request for an id with no view (or a malformed one) gets an empty view: fail closed.
 */
internal class LeadFormViewFactory(private val views: LeadFormViews) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val id = (args as? Map<*, *>)?.get("id") as? String
        val existing = id?.let { views.get(it) }?.webView
        return Attached(existing ?: View(context))
    }

    /** Attaches an existing view; disposing it only detaches, the controller owns the view. */
    private class Attached(private val attached: View) : PlatformView {
        override fun getView(): View = attached

        override fun dispose() {
            (attached.parent as? ViewGroup)?.removeView(attached)
        }
    }
}
