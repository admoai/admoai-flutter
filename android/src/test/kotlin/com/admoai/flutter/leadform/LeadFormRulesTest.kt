package com.admoai.flutter.leadform

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LeadFormRulesTest {
    @Test fun `the origin of an https launch URL is scheme host and port`() {
        assertEquals("https://forms.example.com", LeadFormRules.originOf("https://forms.example.com/runtime/index.html#instanceId=a&channel=b"))
        assertEquals("https://forms.example.com:8443", LeadFormRules.originOf("https://Forms.Example.com:8443/x"))
    }

    @Test fun `an explicit default port is dropped and any other port is kept`() {
        assertEquals("https://forms.example", LeadFormRules.originOf("https://Forms.Example:443/x"))
        assertEquals("https://forms.example:8443", LeadFormRules.originOf("https://forms.example:8443/x"))
        assertFalse(LeadFormRules.sameOrigin(LeadFormRules.originOf("https://forms.example:8443/x")!!, LeadFormRules.originOf("https://forms.example/x")!!))
    }

    @Test fun `anything that is not an https URL with a host has no origin`() {
        for (url in listOf(
            "http://forms.example.com/",
            "file:///etc/hosts",
            "content://x/y",
            "javascript:alert(1)",
            "https:///nohost",
            "https://user:pw@forms.example.com/",
            "not a url",
            "",
        )) {
            assertNull(url, LeadFormRules.originOf(url))
        }
    }

    @Test fun `origins compare ignoring case and a trailing slash`() {
        assertTrue(LeadFormRules.sameOrigin("https://a.example.com/", "https://A.example.com"))
        assertFalse(LeadFormRules.sameOrigin("https://a.example.com", "https://b.example.com"))
        assertFalse(LeadFormRules.sameOrigin("https://a.example.com", "https://a.example.com:444"))
        assertFalse(LeadFormRules.sameOrigin("http://a.example.com", "https://a.example.com"))
    }

    @Test fun `the gate delivers only text from the main frame at the launch origin`() {
        val got = mutableListOf<String>()
        val gate = MessageGate("https://forms.example.com") { got.add(it) }

        assertTrue(gate.offer(true, "https://forms.example.com", true, "one"))
        assertFalse(gate.offer(false, "https://forms.example.com", true, "frame of the same origin"))
        assertFalse(gate.offer(false, "https://evil.example.com", true, "frame of another origin"))
        assertFalse(gate.offer(true, "https://evil.example.com", true, "main frame of another origin"))
        assertFalse(gate.offer(true, "https://forms.example.com", false, "not a text"))
        assertFalse(gate.offer(true, "https://forms.example.com", true, null))
        assertFalse(gate.offer(true, "null", true, "opaque origin"))

        assertEquals(listOf("one"), got)
    }

    private val launch = "https://forms.example.com/runtime/index.html#instanceId=i&channel=c"

    @Test fun `the launch GET is allowed once and a second launch is refused`() {
        assertTrue(LeadFormRules.isAllowedMainFrameLoad(launch, "GET", launch, false))
        assertFalse(LeadFormRules.isAllowedMainFrameLoad(launch, "GET", launch, true))
    }

    @Test fun `a POST to the launch URL is refused`() {
        assertFalse(LeadFormRules.isAllowedMainFrameLoad(launch, "POST", launch, false))
    }

    @Test fun `a GET to another URL is refused`() {
        assertFalse(LeadFormRules.isAllowedMainFrameLoad("https://evil.example.com/", "GET", launch, false))
        assertFalse(LeadFormRules.isAllowedMainFrameLoad("https://forms.example.com/runtime/other.html", "GET", launch, false))
        assertFalse(LeadFormRules.isAllowedMainFrameLoad("https://forms.example.com/runtime/index.html?x=1", "GET", launch, false))
        assertFalse(LeadFormRules.isAllowedMainFrameLoad("http://forms.example.com/runtime/index.html", "GET", launch, false))
    }

    @Test fun `the launch URL matches with a default port and no fragment`() {
        assertTrue(LeadFormRules.isAllowedMainFrameLoad("https://forms.example.com:443/runtime/index.html", "GET", launch, false))
        assertFalse(LeadFormRules.isAllowedMainFrameLoad("https://forms.example.com:8443/runtime/index.html", "GET", launch, false))
    }
}
