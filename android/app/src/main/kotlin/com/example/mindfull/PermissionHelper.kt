package com.example.mindfull

import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat

class PermissionHelper(private val activity: Activity) {

    /**
     * Проверяет, выдано ли разрешение PACKAGE_USAGE_STATS
     */
    fun hasUsageStatsPermission(): Boolean {
        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            activity.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Проверяет, выдано ли разрешение SYSTEM_ALERT_WINDOW
     */
    fun hasOverlayPermission(): Boolean {
        return Settings.canDrawOverlays(activity)
    }

    /**
     * Проверяет, разрешены ли уведомления (Android 13+)
     */
    fun hasNotificationPermission(): Boolean {
        return NotificationManagerCompat.from(activity).areNotificationsEnabled()
    }

    /**
     * Открывает системные настройки Usage Access
     */
    fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }

    /**
     * Открывает системные настройки Overlay для конкретного приложения
     */
    fun requestOverlayPermission() {
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${activity.packageName}")
        )
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(intent)
    }

    /**
     * Открывает настройки уведомлений приложения (Android 13+)
     */
    fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
        }
    }
}