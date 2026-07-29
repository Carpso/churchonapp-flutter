package com.churchonapp.churchonapp

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Listens for incoming notifications from other apps while the device is in
 * Do Not Disturb (DND) mode. This allows the app to track when notifications
 * are shown during DND, supporting the app's emergency-alert and prayer-call
 * features that must break through DND.
 *
 * The app uses this to:
 * - Ensure critical notifications are delivered even during DND
 * - Track notification delivery status for debugging
 *
 * Users are shown a rationale dialog before being asked to grant this access.
 */
class DndNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "ChurchOnApp::DND"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        Log.d(TAG, "Notification posted: ${sbn.packageName} / ${sbn.notification?.tickerText}")
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        Log.d(TAG, "Notification removed: ${sbn.packageName}")
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "DND Notification Listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "DND Notification Listener disconnected")
    }
}
