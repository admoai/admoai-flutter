package com.admoai.flutter.leadform

import android.app.Application
import android.view.ViewGroup
import android.widget.FrameLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * What can be proven about the secure form view without a device: its settings, which origin it
 * binds the bridge to, which messages it lets through, what it does with navigations and windows,
 * what destroy does, and that the factory never creates a view. A real page over HTTPS (an iframe
 * posting, a navigation attempt) needs a device and is not run here.
 *
 * The scenario titles are those of `lib/src/interactive/secure_form_surface.feature`; the Dart test
 * `test/secure_form_surface_test.dart` checks each is named here or in the Dart suite.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SecureFormWebViewTest {
    private val context: Application get() = RuntimeEnvironment.getApplication()
    private val launchUrl = "https://forms.example.com/runtime/index.html#instanceId=i&channel=c"
    private val origin = "https://forms.example.com"

    private class FakeBinder : BridgeBinder {
        var name: String? = null
        var origins: Set<String>? = null
        var listener: ((String, Boolean, Boolean, String?, (String) -> Unit) -> Unit)? = null
        val replies = mutableListOf<String>()

        override fun bind(
            webView: android.webkit.WebView,
            name: String,
            allowedOrigins: Set<String>,
            onMessage: (String, Boolean, Boolean, String?, (String) -> Unit) -> Unit,
        ) {
            this.name = name
            this.origins = allowedOrigins
            this.listener = onMessage
        }

        fun post(sourceOrigin: String, isMainFrame: Boolean, text: String?, isText: Boolean = true) =
            listener!!.invoke(sourceOrigin, isMainFrame, isText, text) { replies.add(it) }
    }

    private class Built(val view: SecureFormWebView, val binder: FakeBinder, val events: MutableList<Pair<SurfaceEventKind, String?>>)

    private fun build(url: String = launchUrl): Built {
        val binder = FakeBinder()
        val events = mutableListOf<Pair<SurfaceEventKind, String?>>()
        val view = SecureFormWebView(context, url, { kind, text -> events.add(kind to text) }, binder, useOwnProfile = false)
        return Built(view, binder, events)
    }

    @Test fun `the form page at the launch origin reaches the app`() {
        val b = build()
        assertEquals("AdmoaiBridge", b.binder.name)
        assertEquals(setOf(origin), b.binder.origins)

        b.binder.post(origin, true, "hello")

        assertEquals(listOf(SurfaceEventKind.MESSAGE to "hello"), b.events)
    }

    @Test fun `the form receives the app's messages`() {
        val b = build()
        b.binder.post(origin, true, "first")

        b.view.send("{\"type\":\"initialize\"}")

        assertEquals(listOf("{\"type\":\"initialize\"}"), b.binder.replies)
    }

    @Test fun `the page learns its instance and channel from the launch URL fragment`() {
        val b = build()

        b.view.load()

        assertEquals(launchUrl, shadowOf(b.view.webView).lastLoadedUrl)
    }

    @Test fun `a frame from another origin cannot reach the app`() {
        val b = build()

        b.binder.post("https://evil.example.com", false, "frame")

        assertTrue(b.events.isEmpty())
        assertNull("nothing to reply to", run { b.view.send("x"); b.binder.replies.firstOrNull() })
    }

    @Test fun `a frame from the same origin cannot reach the app`() {
        val b = build()

        b.binder.post(origin, false, "frame")

        assertTrue(b.events.isEmpty())
    }

    @Test fun `the form cannot navigate away`() {
        val b = build()
        val client = shadowOf(b.view.webView).webViewClient
        val request = object : android.webkit.WebResourceRequest {
            override fun getUrl() = android.net.Uri.parse("https://evil.example.com/")
            override fun isForMainFrame() = true
            override fun isRedirect() = false
            override fun hasGesture() = true
            override fun getMethod() = "GET"
            override fun getRequestHeaders(): Map<String, String> = emptyMap()
        }

        assertTrue(client.shouldOverrideUrlLoading(b.view.webView, request))
    }

    @Test fun `the form cannot open windows or popups`() {
        val b = build()
        val s = b.view.webView.settings

        assertFalse(s.javaScriptCanOpenWindowsAutomatically)
        assertFalse(s.supportMultipleWindows())
        val chrome = shadowOf(b.view.webView).webChromeClient
        assertFalse(chrome.onCreateWindow(b.view.webView, false, true, android.os.Message.obtain()))
    }

    @Test fun `files and content providers are out of reach`() {
        val s = build().view.webView.settings

        assertFalse(s.allowFileAccess)
        assertFalse(s.allowContentAccess)
        @Suppress("DEPRECATION")
        assertFalse(s.allowFileAccessFromFileURLs)
        @Suppress("DEPRECATION")
        assertFalse(s.allowUniversalAccessFromFileURLs)
    }

    @Test fun `the form view is locked down`() {
        val s = build().view.webView.settings

        assertTrue(s.javaScriptEnabled)
        assertFalse(s.allowFileAccess)
        assertFalse(s.allowContentAccess)
        assertEquals(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW, s.mixedContentMode)
        assertFalse(s.supportMultipleWindows())
        assertFalse(s.domStorageEnabled)
        @Suppress("DEPRECATION")
        assertFalse(s.databaseEnabled)
        assertFalse(s.javaScriptCanOpenWindowsAutomatically)
    }

    @Test fun `destroying the view removes the bridge`() {
        val b = build()
        val parent = FrameLayout(context)
        parent.addView(b.view.webView)
        b.binder.post(origin, true, "before")

        b.view.destroy()
        b.binder.post(origin, true, "after")
        b.view.send("late")

        assertEquals(listOf(SurfaceEventKind.MESSAGE to "before"), b.events)
        assertTrue(b.binder.replies.isEmpty())
        assertNull(b.view.webView.parent)
        assertEquals(0, parent.childCount)
        b.view.destroy() // safe to repeat
    }

    @Test fun `a launch URL that is not https never makes a view`() {
        for (url in listOf("http://forms.example.com/", "file:///x", "javascript:1", "")) {
            try {
                build(url)
                fail("a view was created for $url")
            } catch (_: IllegalArgumentException) {
                // refused
            }
        }
    }

    @Test fun `a main frame load error is reported and a render process loss destroys the view`() {
        val b = build()
        val client = shadowOf(b.view.webView).webViewClient

        client.onReceivedHttpError(
            b.view.webView,
            object : android.webkit.WebResourceRequest {
                override fun getUrl() = android.net.Uri.parse(launchUrl)
                override fun isForMainFrame() = true
                override fun isRedirect() = false
                override fun hasGesture() = false
                override fun getMethod() = "GET"
                override fun getRequestHeaders(): Map<String, String> = emptyMap()
            },
            android.webkit.WebResourceResponse("text/html", "utf-8", 503, "Unavailable", emptyMap(), java.io.ByteArrayInputStream(ByteArray(0))),
        )
        assertEquals(listOf(SurfaceEventKind.LOAD_FAILED to null), b.events)

        val handled = client.onRenderProcessGone(
            b.view.webView,
            object : android.webkit.RenderProcessGoneDetail() {
                override fun didCrash() = true
                override fun rendererPriorityAtExit() = 0
            },
        )
        assertTrue(handled)
        assertEquals(SurfaceEventKind.RENDER_GONE, b.events.last().first)
    }

    @Test fun `the platform view factory never creates a view`() {
        val views = LeadFormViews()
        val factory = LeadFormViewFactory(views)
        val b = build()
        views.put("lead_form_1", b.view)

        val known = factory.create(context, 1, mapOf("id" to "lead_form_1"))
        val unknown = factory.create(context, 2, mapOf("id" to "lead_form_9"))
        val malformed = factory.create(context, 3, "not a map")

        assertSame(b.view.webView, known.view)
        assertFalse(unknown.view is android.webkit.WebView)
        assertFalse(malformed.view is android.webkit.WebView)
        assertNull(views.get("lead_form_9"))

        // Disposing the platform view detaches the view; it does not destroy it.
        val parent: ViewGroup = FrameLayout(context)
        parent.addView(known.view!!)
        known.dispose()
        assertNull(known.view!!.parent)
        b.binder.post(origin, true, "still alive")
        assertEquals(1, b.events.size)
    }
}
