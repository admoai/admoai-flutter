package com.admoai.flutter.leadform

import android.annotation.SuppressLint
import android.content.Context
import android.content.MutableContextWrapper
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ProfileStore
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicBoolean

/** What the page and the view report to Dart, by the names the Dart side reads. */
internal enum class SurfaceEventKind(val wire: String) {
    MESSAGE("message"),
    RENDER_GONE("renderGone"),
    LOAD_FAILED("loadFailed"),
}

/**
 * The string of a page message, or null for any other type. The data is read only for a text: an
 * ArrayBuffer message has no string data and reading it throws.
 */
internal fun textOf(message: WebMessageCompat): String? =
    if (message.type == WebMessageCompat.TYPE_STRING) message.data else null

/** Binds the page's bridge object. The real one is [WebViewCompat]; tests replace it. */
internal fun interface BridgeBinder {
    fun bind(
        webView: WebView,
        name: String,
        allowedOrigins: Set<String>,
        onMessage: (sourceOrigin: String, isMainFrame: Boolean, isText: Boolean, data: String?, reply: (String) -> Unit) -> Unit,
    )

    companion object {
        val Real = BridgeBinder { webView, name, origins, onMessage ->
            WebViewCompat.addWebMessageListener(webView, name, origins) { _, message, sourceOrigin, isMainFrame, proxy ->
                val text = textOf(message)
                onMessage(sourceOrigin.toString(), isMainFrame, text != null, text) { text -> proxy.postMessage(text) }
            }
        }
    }
}

/**
 * The secure form view: a WebView that only the form's own origin can talk to.
 *
 * - One injected object, `AdmoaiBridge`, exists only in frames of the launch origin; the app listens
 *   only to the main frame of that origin and only to text messages.
 * - Every navigation the page starts is blocked, no window can open, no file or content address can
 *   load, DOM storage is off and the view uses its own WebView profile where the device has one.
 * - Created with the application context; while attached to a window it borrows the parent's context
 *   (so selects and the keyboard work) and gives it back on detach, never keeping an Activity.
 *
 * Nothing the page sends and no URL with a query string is ever logged. Main thread only.
 */
internal class SecureFormWebView(
    context: Context,
    launchUrl: String,
    private val onEvent: (SurfaceEventKind, String?) -> Unit,
    binder: BridgeBinder = BridgeBinder.Real,
    useOwnProfile: Boolean = defaultProfileSupport(),
) {
    private val launchOrigin: String =
        LeadFormRules.originOf(launchUrl) ?: throw IllegalArgumentException("The launch URL is not an https URL")
    private val launchUrlWithoutFragment: String = launchUrl.substringBefore('#')
    private val launchUrlText: String = launchUrl
    private val contextWrapper = MutableContextWrapper(context.applicationContext ?: context)
    private val appContext: Context = contextWrapper.baseContext

    val webView: WebView = WebView(contextWrapper)

    private var reply: ((String) -> Unit)? = null
    private var destroyed = false

    init {
        if (useOwnProfile) bindOwnProfile(webView)
        configure(webView.settings)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        webView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) {
                (v.parent as? View)?.context?.let { contextWrapper.baseContext = it }
            }

            override fun onViewDetachedFromWindow(v: View) {
                contextWrapper.baseContext = appContext
            }
        })
        webView.webViewClient = FormClient()
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message,
            ): Boolean = false
        }
        val gate = MessageGate(launchOrigin) { text -> onEvent(SurfaceEventKind.MESSAGE, text) }
        binder.bind(webView, LeadFormRules.BRIDGE_NAME, setOf(launchOrigin)) { sourceOrigin, isMainFrame, isText, data, replyTo ->
            if (!destroyed && gate.offer(isMainFrame, sourceOrigin, isText, data)) reply = replyTo
        }
    }

    /** Loads the launch URL: the one load this view ever makes by itself. */
    fun load() {
        if (!destroyed) webView.loadUrl(launchUrlText)
    }

    /** Sends one text to the page, through the reply channel of its last accepted message. */
    fun send(text: String) {
        if (!destroyed) reply?.invoke(text)
    }

    /** Removes the bridge, stops loading and releases the view. Safe to repeat. */
    fun destroy() {
        if (destroyed) return
        destroyed = true
        reply = null
        try {
            WebViewCompat.removeWebMessageListener(webView, LeadFormRules.BRIDGE_NAME)
        } catch (_: Throwable) {
            // The view is going away either way.
        }
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.stopLoading()
        webView.destroy()
        contextWrapper.baseContext = appContext
    }

    private inner class FormClient : WebViewClient() {
        // shouldInterceptRequest runs off the main thread, so the launch is consumed atomically.
        private val launchConsumed = AtomicBoolean(false)
        private val mainHandler = Handler(Looper.getMainLooper())

        // shouldOverrideUrlLoading is never called for a POST form submission, so every main-frame
        // request is judged here: only the first GET of the launch URL loads; anything else loads
        // nothing and fails the form, which can no longer be trusted to be on screen.
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            // Debug-only fixture server for the on-device test; in release and profile builds
            // FormTestHooks (src/nonDebug) always answers null, so the WebView loads from the network.
            if (!request.isForMainFrame) return FormTestHooks.intercept(request)
            val isLaunch = LeadFormRules.isAllowedMainFrameLoad(
                request.url.toString(), request.method, launchUrlText, launchConsumed.get(),
            ) && launchConsumed.compareAndSet(false, true)
            if (isLaunch) return FormTestHooks.intercept(request)
            mainHandler.post { fail(LOAD_BLOCKED) }
            return WebResourceResponse("text/plain", "utf-8", 204, "No Content", emptyMap(), ByteArrayInputStream(ByteArray(0)))
        }

        // Belt and braces: whatever slipped past the interception is stopped here.
        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            // Same comparison as the interception (fragment and a default :443 ignored); the
            // launch itself is already consumed by now, so it is judged as a fresh launch here.
            if (url == null || !LeadFormRules.isAllowedMainFrameLoad(url, "GET", launchUrlText, false)) {
                view.stopLoading()
                fail(LOAD_BLOCKED)
            }
        }

        // Every navigation the page starts (link, redirect, script) is blocked: the one load this
        // view makes is the launch URL, which goes through loadUrl and never reaches this method.
        // A main-frame one also fails the form, which can no longer be trusted to be on screen; a
        // subframe one is cancelled silently.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (request.isForMainFrame) fail(LOAD_BLOCKED)
            return true
        }

        // API 21-23 call this overload instead of the one above. It carries no frame and may be
        // called for subframes, so it cancels without failing the form: an iframe navigating
        // must not end it. A main-frame load that still reaches the network is caught by
        // shouldInterceptRequest.
        @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean = true

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (request.isForMainFrame) fail(LOAD_NETWORK)
        }

        override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse) {
            if (request.isForMainFrame && errorResponse.statusCode >= 400) fail("http:${errorResponse.statusCode}")
        }

        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
            handler.cancel()
            if (error.url?.substringBefore('#') == launchUrlWithoutFragment) fail(LOAD_NETWORK)
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            val callback = onEvent
            destroy()
            callback(SurfaceEventKind.RENDER_GONE, null)
            return true
        }

        // The reason travels as the event's text: "http:<status>", "network" or "blocked".
        private fun fail(reason: String) {
            if (!destroyed) onEvent(SurfaceEventKind.LOAD_FAILED, reason)
        }
    }

    @SuppressLint("RequiresFeature")
    private fun bindOwnProfile(webView: WebView) {
        ProfileStore.getInstance().getOrCreateProfile(LeadFormRules.PROFILE)
        WebViewCompat.setProfile(webView, LeadFormRules.PROFILE)
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Suppress("DEPRECATION")
    private fun configure(settings: WebSettings) {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = false
        settings.databaseEnabled = false
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.allowFileAccessFromFileURLs = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.setSupportMultipleWindows(false)
        settings.javaScriptCanOpenWindowsAutomatically = false
        settings.setGeolocationEnabled(false)
    }

    companion object {
        const val LOAD_NETWORK = "network"
        const val LOAD_BLOCKED = "blocked"

        @SuppressLint("RequiresFeature")
        fun defaultProfileSupport(): Boolean = try {
            WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
        } catch (_: Throwable) {
            false
        }
    }
}
