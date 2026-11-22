package com.admoai.flutter.leadform

import android.content.Context
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The release and profile half of the test hooks: they do nothing. The debug half lives in
 * `src/debug` (see build.gradle) and serves fixture pages for the on-device test; a release or
 * profile build never compiles it, so no hook method exists there and the production web view
 * answers every request exactly as it did before the hooks.
 */
internal object FormTestHooks {
    fun intercept(request: WebResourceRequest): WebResourceResponse? = null

    fun handle(call: MethodCall, result: MethodChannel.Result, context: Context, views: LeadFormViews): Boolean =
        false
}
