package com.admoai.flutter.leadform

import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import androidx.webkit.WebViewAssetLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Debug builds only (`src/debug`): what integration_test/secure_form_surface_test.dart needs to run
 * the form's pages over https on a real WebView. Serves the Flutter assets of the host app from
 * `https://appassets.androidplatform.net/assets/` and, as a second origin,
 * `https://other.appassets.example/assets/`, with [WebViewAssetLoader]. Nothing is served until the
 * test asks (`testServeFixtures`). The release and profile builds compile `src/nonDebug` instead,
 * where every function is a no-op, so this class does not exist there.
 *
 * Main thread only, like the rest of the form view.
 */
internal object FormTestHooks {
    private var loaders: List<WebViewAssetLoader>? = null
    private val requests = CopyOnWriteArrayList<String>()

    /** Answers a page request from the fixtures, or null to leave it to the WebView. */
    fun intercept(request: WebResourceRequest): WebResourceResponse? {
        val active = loaders ?: return null
        requests += request.url.toString()
        for (loader in active) {
            loader.shouldInterceptRequest(request.url)?.let { return it }
        }
        return null
    }

    fun handle(call: MethodCall, result: MethodChannel.Result, context: Context, views: LeadFormViews): Boolean {
        when (call.method) {
            "testServeFixtures" -> {
                loaders = listOf(
                    WebViewAssetLoader.Builder()
                        .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
                        .build(),
                    WebViewAssetLoader.Builder()
                        .setDomain("other.appassets.example")
                        .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
                        .build(),
                )
                requests.clear()
                result.success(null)
            }
            "testReset" -> {
                loaders = null
                requests.clear()
                result.success(null)
            }
            "testClearRequests" -> {
                requests.clear()
                result.success(null)
            }
            "testRequests" -> result.success(requests.toList())
            "testCurrentUrl" -> result.success(call.argument<String>("id")?.let { views.get(it) }?.webView?.url)
            else -> return false
        }
        return true
    }
}
