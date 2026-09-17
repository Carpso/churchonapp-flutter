package com.churchonapp.churchonapp

import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.churchonapp.churchonapp/dnd_helper"
    private val WAKE_CHANNEL = "com.churchonapp.churchonapp/wake_service"
    private val SCREENSHOT_CHANNEL = "com.churchonapp.churchonapp/screenshot"
    private var monitorHandler: Handler? = null
    private var monitorRunnable: Runnable? = null
    private val blockedPackagesList = mutableSetOf<String>()
    private var screenshotObserver: ContentObserver? = null
    private var screenshotChannel: MethodChannel? = null
    private var lastShotAt = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupScreenshotChannel(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

            when (call.method) {
                "isDndAvailable" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                }
                "hasDndPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(notificationManager?.isNotificationPolicyAccessGranted ?: false)
                    } else {
                        result.success(true)
                    }
                }
                "openDndSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_DND_FAILED", e.message, null)
                    }
                }
                "enableDnd" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && notificationManager != null) {
                            if (notificationManager.isNotificationPolicyAccessGranted) {
                                notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("ENABLE_DND_FAILED", e.message, null)
                    }
                }
                "disableDnd" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && notificationManager != null) {
                            if (notificationManager.isNotificationPolicyAccessGranted) {
                                notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("DISABLE_DND_FAILED", e.message, null)
                    }
                }
                "isDndEnabled" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && notificationManager != null) {
                        val filter = notificationManager.currentInterruptionFilter
                        result.success(filter != NotificationManager.INTERRUPTION_FILTER_ALL)
                    } else {
                        result.success(false)
                    }
                }
                "hasUsagePermission" -> {
                    val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        appOps?.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
                    } else {
                        @Suppress("DEPRECATION")
                        appOps?.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
                    }
                    result.success(mode == AppOpsManager.MODE_ALLOWED)
                }
                "openUsageSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_USAGE_FAILED", e.message, null)
                    }
                }
                "startAppMonitor" -> {
                    val packages = call.argument<List<String>>("blockedPackages")
                    blockedPackagesList.clear()
                    if (packages != null && packages.isNotEmpty()) {
                        blockedPackagesList.addAll(packages)
                    } else {
                        blockedPackagesList.addAll(listOf(
                            "com.instagram.android",
                            "com.zhiliaoapp.musically", // TikTok
                            "com.facebook.katana",
                            "com.facebook.orca",
                            "com.twitter.android",
                            "com.snapchat.android",
                            "com.google.android.youtube",
                            "com.netflix.mediaclient",
                            "com.pinterest",
                            "com.linkedin.android"
                        ))
                    }
                    startMonitoring()
                    result.success(true)
                }
                "stopAppMonitor" -> {
                    stopMonitoring()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Wake service: turn screen on for critical notifications (ride, SOS)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "wakeScreen" -> {
                    try {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val isInteractive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                            powerManager.isInteractive
                        } else {
                            @Suppress("DEPRECATION")
                            powerManager.isScreenOn
                        }
                        if (!isInteractive) {
                            @Suppress("DEPRECATION")
                            val wakeLock = powerManager.newWakeLock(
                                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                                "churchonapp:wake"
                            )
                            wakeLock.acquire(5000L)
                        }
                        runOnUiThread {
                            try {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                                )
                                // Clear KEEP_SCREEN_ON after delay to avoid battery drain
                                Handler(Looper.getMainLooper()).postDelayed({
                                    try {
                                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                    } catch (_: Exception) {}
                                }, 5000L)
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Screenshot detection ────────────────────────────────────────────────
    // Detects a taken screenshot (does NOT block it) and notifies Dart so the
    // app can offer a "share instead" sheet.
    private fun setupScreenshotChannel(flutterEngine: FlutterEngine) {
        screenshotChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL
        )
        screenshotChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startWatching" -> { startScreenshotWatch(); result.success(true) }
                "stopWatching" -> { stopScreenshotWatch(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    private fun startScreenshotWatch() {
        if (screenshotObserver != null) return
        try {
            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    val now = System.currentTimeMillis()
                    if (now - lastShotAt < 1500) return
                    if (isScreenshot(uri)) {
                        lastShotAt = now
                        runOnUiThread {
                            screenshotChannel?.invokeMethod("screenshot", null)
                        }
                    }
                }
            }
            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, observer
            )
            screenshotObserver = observer
        } catch (_: Exception) {
        }
    }

    private fun stopScreenshotWatch() {
        try {
            screenshotObserver?.let { contentResolver.unregisterContentObserver(it) }
        } catch (_: Exception) {
        }
        screenshotObserver = null
    }

    private fun isScreenshot(uri: Uri?): Boolean {
        if (uri == null) return false
        return try {
            val cols = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(
                    MediaStore.Images.Media.DISPLAY_NAME,
                    MediaStore.Images.Media.RELATIVE_PATH,
                    MediaStore.Images.Media.DATE_ADDED
                )
            } else {
                arrayOf(
                    MediaStore.Images.Media.DATA,
                    MediaStore.Images.Media.DATE_ADDED
                )
            }
            contentResolver.query(uri, cols, null, null, null)?.use { c ->
                if (!c.moveToFirst()) return false
                val added = c.getLong(c.getColumnIndex(MediaStore.Images.Media.DATE_ADDED))
                val fresh = (System.currentTimeMillis() / 1000 - added) < 10
                val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    c.getString(c.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH))
                } else {
                    c.getString(c.getColumnIndex(MediaStore.Images.Media.DATA))
                }
                fresh && (path?.contains("screenshot", ignoreCase = true) == true)
            } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun startMonitoring() {
        stopMonitoring()
        monitorHandler = Handler(Looper.getMainLooper())
        monitorRunnable = object : Runnable {
            override fun run() {
                checkForegroundApp()
                monitorHandler?.postDelayed(this, 1200)
            }
        }
        monitorHandler?.postDelayed(monitorRunnable!!, 1000)
    }

    private fun stopMonitoring() {
        monitorRunnable?.let { monitorHandler?.removeCallbacks(it) }
        monitorHandler = null
        monitorRunnable = null
    }

    private fun checkForegroundApp() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return
        val time = System.currentTimeMillis()
        val events = usageStatsManager.queryEvents(time - 3000, time) ?: return

        var fgPackage: String? = null
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED || event.eventType == 1) { // 1 = MOVE_TO_FOREGROUND
                fgPackage = event.packageName
            }
        }

        if (fgPackage != null && fgPackage != packageName && blockedPackagesList.contains(fgPackage)) {
            val bringIntent = Intent(applicationContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("blocked_app_intercepted", fgPackage)
            }
            startActivity(bringIntent)
        }
    }

    override fun onDestroy() {
        stopMonitoring()
        stopScreenshotWatch()
        super.onDestroy()
    }
}
