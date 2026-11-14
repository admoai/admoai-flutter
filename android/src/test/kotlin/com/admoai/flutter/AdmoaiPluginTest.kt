package com.admoai.flutter

import android.content.res.Configuration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdmoaiPluginTest {
    private val none = emptySet<String>()
    private val normal = Configuration.UI_MODE_TYPE_NORMAL
    private val undefined = Configuration.UI_MODE_TYPE_UNDEFINED

    @Test fun width599Point9IsPhone() =
        assertEquals("phone", DeviceSignalRules.classify(none, normal, 599.9f))

    @Test fun width600IsTablet() =
        assertEquals("tablet", DeviceSignalRules.classify(none, normal, 600f))

    @Test fun undefinedModeUsesWidth() {
        assertEquals("phone", DeviceSignalRules.classify(none, undefined, 599.9f))
        assertEquals("tablet", DeviceSignalRules.classify(none, undefined, 600f))
    }

    @Test fun specialFeaturesAreOther() {
        for (f in listOf(
            "android.software.leanback",
            "android.hardware.type.watch",
            "android.hardware.type.automotive",
            "android.hardware.type.pc",
        )) {
            assertEquals("other", DeviceSignalRules.classify(setOf(f), normal, 400f))
        }
    }

    @Test fun televisionModeIsOther() =
        assertEquals("other", DeviceSignalRules.classify(none, Configuration.UI_MODE_TYPE_TELEVISION, 400f))

    @Test fun watchModeIsOther() =
        assertEquals("other", DeviceSignalRules.classify(none, Configuration.UI_MODE_TYPE_WATCH, 400f))

    @Test fun carModeKeepsPhone() =
        assertEquals("phone", DeviceSignalRules.classify(none, Configuration.UI_MODE_TYPE_CAR, 400f))

    @Test fun deskModeKeepsTablet() =
        assertEquals("tablet", DeviceSignalRules.classify(none, Configuration.UI_MODE_TYPE_DESK, 800f))

    @Test fun carModeWithNullWidthIsAbsent() =
        assertNull(DeviceSignalRules.classify(none, Configuration.UI_MODE_TYPE_CAR, null))

    @Test fun nullWidthIsAbsent() = assertNull(DeviceSignalRules.classify(none, normal, null))

    @Test fun unknownModeIsNotOther() =
        assertEquals("phone", DeviceSignalRules.classify(none, null, 360f))

    @Test fun featureBeatsWidth() =
        assertEquals("other", DeviceSignalRules.classify(setOf("android.software.leanback"), normal, 1000f))

    @Test fun unrelatedFeatureDoesNotMakeOther() =
        assertEquals("phone", DeviceSignalRules.classify(setOf("android.hardware.camera"), normal, 360f))

    @Test fun carrierRequiresApi24() {
        assertFalse(DeviceSignalRules.normalizeSubscription(1, 23, true))
        assertTrue(DeviceSignalRules.normalizeSubscription(1, 24, true))
    }

    @Test fun carrierRequiresTelephony() =
        assertFalse(DeviceSignalRules.normalizeSubscription(1, 34, false))

    @Test fun carrierRequiresValidDefaultDataSubscription() =
        assertFalse(DeviceSignalRules.normalizeSubscription(-1, 34, true))

    @Test fun hardwareProbeRunsOncePerProcessWhileWidthRunsPerRead() {
        val cache = HardwareClassCache()
        var probes = 0
        var widths = 0
        repeat(3) {
            assertEquals(
                "phone",
                readCategoryWith(cache, { probes++; false }, { widths++; 360f }),
            )
        }
        assertEquals(1, probes)
        assertEquals(3, widths)
    }

    @Test fun otherHardwareIsCachedAndSkipsWidth() {
        val cache = HardwareClassCache()
        var probes = 0
        repeat(2) {
            assertEquals("other", readCategoryWith(cache, { probes++; true }, { error("not read") }))
        }
        assertEquals(1, probes)
    }

    @Test fun throwingHardwareProbeIsRetriedOnNextRead() {
        val cache = HardwareClassCache()
        var probes = 0
        val probe = { probes++; if (probes == 1) error("boom") else true }
        assertEquals("phone", readCategoryWith(cache, probe, { 360f }))
        assertEquals("other", readCategoryWith(cache, probe, { 360f }))
        assertEquals(2, probes)
    }

    @Test fun featureAnswersWithoutReadingUiMode() =
        assertTrue(hardwareIsOther(setOf("android.software.leanback")) { error("not read") })

    @Test fun failedUiModeReadFallsBackToWidthAndIsRetried() {
        val cache = HardwareClassCache()
        var reads = 0
        val uiMode = {
            reads++
            if (reads == 1) error("UiModeManager unavailable") else Configuration.UI_MODE_TYPE_TELEVISION
        }
        val probe = { hardwareIsOther(none, uiMode) }
        assertEquals("phone", readCategoryWith(cache, probe, { 360f }))
        assertEquals("other", readCategoryWith(cache, probe, { 360f }))
        assertEquals(2, reads)
    }
}
