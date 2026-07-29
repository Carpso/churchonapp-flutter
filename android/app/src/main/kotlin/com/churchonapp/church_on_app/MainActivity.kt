package com.churchonapp.churchonapp

import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.churchonapp.churchonapp/dnd_helper"
    private var monitorHandler: Handler? = null
    private var monitorRunnable: Runnable? = null
    private val blockedPackagesList = mutableSetOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        super.onDestroy()
    }
}
