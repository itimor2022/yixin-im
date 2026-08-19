package com.genericim.ma100

import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidNotificationIdentityTest {
    @Test
    fun fcmAutomaticMessageIdentityMatchesServerContract() {
        assertEquals(0, AndroidNotificationIdentity.fcmAutomaticNotificationId)
        assertEquals(
            "genericim-message-48082",
            AndroidNotificationIdentity.messageTag(48082),
        )
    }
}
