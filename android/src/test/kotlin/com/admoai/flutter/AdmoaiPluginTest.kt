package com.admoai.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdmoaiPluginTest {
    @Test fun width599Point9IsPhone() =
        assertEquals("phone", DeviceSignalRules.classify(emptySet(), 599.9f))

    @Test fun width600IsTablet() =
        assertEquals("tablet", DeviceSignalRules.classify(emptySet(), 600f))

    @Test fun specialFeaturesAreOther() {
        for (f in listOf(
            "android.software.leanback",
            "android.hardware.type.watch",
            "android.hardware.type.automotive",
            "android.hardware.type.pc",
        )) {
            assertEquals("other", DeviceSignalRules.classify(setOf(f), 400f))
        }
    }

    @Test fun nullWidthIsAbsent() = assertNull(DeviceSignalRules.classify(emptySet(), null))

    @Test fun unrelatedFeatureDoesNotMakeOther() =
        assertEquals("phone", DeviceSignalRules.classify(setOf("android.hardware.camera"), 360f))

    @Test fun carrierRequiresApi24() {
        assertFalse(DeviceSignalRules.normalizeSubscription(1, 23, true))
        assertTrue(DeviceSignalRules.normalizeSubscription(1, 24, true))
    }

    @Test fun carrierRequiresTelephony() =
        assertFalse(DeviceSignalRules.normalizeSubscription(1, 34, false))

    @Test fun carrierRequiresValidDefaultDataSubscription() =
        assertFalse(DeviceSignalRules.normalizeSubscription(-1, 34, true))
}
