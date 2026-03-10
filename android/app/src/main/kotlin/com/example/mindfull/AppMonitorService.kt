package com.example.mindfull

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class AppMonitorService : Service() {

    companion object {
        const val ACTION_START = "com.example.mindfull.START"
        const val ACTION_STOP = "com.example.mindfull.STOP"

        private const val TAG = "AppMonitorService"
        private const val CHANNEL_ID = "mindful_pause_monitor"
        private const val NOTIFICATION_ID = 1001
        private const val POLL_INTERVAL_MS = 500L // Проверяем каждые 500мс
        private const val COOLDOWN_MS = 5 * 60 * 1000L // 5 минут cooldown
        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_MONITORED = "monitored_packages"

        @Volatile
        var isRunning = false
            private set

        /**
         * Обновляет список отслеживаемых пакетов (вызывается из Flutter)
         */
        fun updateMonitoredPackages(context: Context, packages: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(KEY_MONITORED, packages.toSet()).apply()
            Log.d(TAG, "Updated monitored packages: $packages")
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var usageStatsManager: UsageStatsManager? = null
    private lateinit var prefs: SharedPreferences

    // Cooldown: packageName -> timestamp последнего срабатывания
    private val cooldownMap = mutableMapOf<String, Long>()
    private var lastForegroundPackage: String? = null

    private val pollRunnable = object : Runnable {
        override fun run() {
            checkForegroundApp()
            if (isRunning) {
                handler.postDelayed(this, POLL_INTERVAL_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                isRunning = false
                handler.removeCallbacks(pollRunnable)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                Log.d(TAG, "Service stopped via ACTION_STOP")
                return START_NOT_STICKY
            }
            else -> {
                startForegroundWithNotification()
                isRunning = true
                handler.post(pollRunnable)
                Log.d(TAG, "Service started")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(pollRunnable)
        Log.d(TAG, "Service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Foreground Notification ──

    private fun startForegroundWithNotification() {
        val channelName = "Мониторинг приложений"
        val channel = NotificationChannel(
            CHANNEL_ID,
            channelName,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mindful Pause отслеживает запуск приложений"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Mindful Pause")
            .setContentText("Защита активна")
            .setSmallIcon(android.R.drawable.ic_menu_compass) // TODO: заменить на свою иконку
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    // ── Определение foreground-приложения ──

    private fun checkForegroundApp() {
        val currentPackage = getForegroundPackage() ?: return

        // Если foreground не изменился — ничего не делаем
        if (currentPackage == lastForegroundPackage) return
        lastForegroundPackage = currentPackage

        // Проверяем, есть ли пакет в отслеживаемых
        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()
        if (currentPackage !in monitored) return

        // Проверяем cooldown
        val now = System.currentTimeMillis()
        val lastTriggered = cooldownMap[currentPackage] ?: 0L
        if (now - lastTriggered < COOLDOWN_MS) {
            Log.d(TAG, "Cooldown active for $currentPackage")
            return
        }

        // Пакет в списке, cooldown прошёл → показываем паузу
        cooldownMap[currentPackage] = now
        Log.d(TAG, "Intercepted: $currentPackage → showing pause screen")
        showPauseOverlay(currentPackage)
    }

    private fun getForegroundPackage(): String? {
        val now = System.currentTimeMillis()
        val stats = usageStatsManager?.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 10_000, // последние 10 секунд
            now
        )
        if (stats.isNullOrEmpty()) return null

        // Берём приложение с самым свежим lastTimeUsed
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    // ── Показ Pause Overlay ──

    private fun showPauseOverlay(targetPackage: String) {
        Log.d(TAG, "Showing pause for $targetPackage")

        // Получаем человекочитаемое имя приложения
        val appName = try {
            val appInfo = packageManager.getApplicationInfo(targetPackage, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            targetPackage
        }

        val intent = Intent(this, PauseActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(PauseActivity.EXTRA_TARGET_PACKAGE, targetPackage)
            putExtra(PauseActivity.EXTRA_APP_NAME, appName)
        }
        startActivity(intent)
    }
}