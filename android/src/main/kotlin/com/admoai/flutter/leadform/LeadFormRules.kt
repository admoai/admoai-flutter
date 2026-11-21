package com.admoai.flutter.leadform

import java.net.URI

/**
 * The pure decisions behind the secure form view, separated from the WebView so they run in a plain
 * JVM unit test. Everything fails closed: anything that is not exactly what is expected is refused.
 */
internal object LeadFormRules {
    const val BRIDGE_NAME = "AdmoaiBridge"
    const val PROFILE = "admoai_interactive_experience"

    /**
     * The origin (`https://host[:port]`, the default port 443 dropped) of [url], or null when [url] is not an https URL with a
     * host and no user info. The page's origin is the only one the bridge ever listens to.
     */
    fun originOf(url: String): String? = try {
        val uri = URI(url)
        val host = uri.host
        if (!"https".equals(uri.scheme, ignoreCase = true) || host.isNullOrEmpty() || uri.userInfo != null) {
            null
        } else {
            "https://${host.lowercase()}" + if (uri.port != -1 && uri.port != 443) ":${uri.port}" else ""
        }
    } catch (_: Exception) {
        null
    }

    /** True when two origins are the same, ignoring case and a trailing slash. */
    fun sameOrigin(a: String, b: String): Boolean =
        a.trimEnd('/').equals(b.trimEnd('/'), ignoreCase = true)
}

/**
 * Lets a message through only when it comes from the main frame at the launch origin and is a text.
 * A frame, whatever its origin, and anything that is not a string never reaches the app.
 */
internal class MessageGate(private val launchOrigin: String, private val deliver: (String) -> Unit) {
    /** Returns true when the message was delivered. */
    fun offer(isMainFrame: Boolean, sourceOrigin: String, isText: Boolean, data: String?): Boolean {
        if (!isMainFrame || !isText || data == null) return false
        if (!LeadFormRules.sameOrigin(sourceOrigin, launchOrigin)) return false
        deliver(data)
        return true
    }
}
