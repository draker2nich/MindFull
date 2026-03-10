package com.example.mindfull

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Перезапускает AppMonitorService после:
 * - Перезагрузки устройства (BOOT_COMPLETED)
 * - Обновления приложения (MY_PACKAGE_REPLACED)
 *
 * Сервис стартует только если пользователь ранее включил защиту
 * и есть выбранные приложения для мониторинга.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_SERVICE_ENABLED = "service_enabled"
        private const val KEY_MONITORED = "monitored_packages"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        Log.d(TAG, "Received: $action")

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_SERVICE_ENABLED, false)
        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()

        if (!enabled || monitored.isEmpty()) {
            Log.d(TAG, "Service not enabled or no monitored apps — skipping")
            return
        }

        Log.d(TAG, "Restarting AppMonitorService (${monitored.size} apps monitored)")

        val serviceIntent = Intent(context, AppMonitorService::class.java).apply {
            this.action = AppMonitorService.ACTION_START
        }

        try {
            context.startForegroundService(serviceIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service after boot", e)
        }
    }
}