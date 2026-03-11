package com.example.mindfull

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

class AppMonitorService : Service() {

    companion object {
        const val ACTION_START = "com.example.mindfull.START"
        const val ACTION_STOP = "com.example.mindfull.STOP"

        private const val TAG = "AppMonitorService"
        private const val CHANNEL_ID = "mindful_pause_monitor"
        private const val NOTIFICATION_ID = 1001
        private const val POLL_INTERVAL_MS = 500L
        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_MONITORED = "monitored_packages"
        private const val KEY_COOLDOWN_MINUTES = "cooldown_minutes"
        private const val KEY_COOLDOWN_PREFIX = "cooldown_"

        // Пакеты, которые никогда не перехватываем
        private val IGNORED_PACKAGES = setOf(
            "com.example.mindfull",
            "com.android.systemui",
            "com.android.launcher",
            "com.android.launcher3",
            "com.google.android.apps.nexuslauncher",
            "com.sec.android.app.launcher", // Samsung
            "com.miui.home",                // Xiaomi
            "com.huawei.android.launcher",  // Huawei
        )

        @Volatile
        var isRunning = false
            private set

        fun updateMonitoredPackages(context: Context, packages: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(KEY_MONITORED, packages.toSet()).apply()
            Log.d(TAG, "Updated monitored packages: $packages")
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var usageStatsManager: UsageStatsManager? = null
    private lateinit var prefs: SharedPreferences
    private var powerManager: PowerManager? = null
    private var lastForegroundPackage: String? = null
    private var isScreenOn = true
    private var pauseShowing = false
    private var pauseDismissedAt: Long = 0 // Защита от race condition

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOn = false
                    handler.removeCallbacks(pollRunnable)
                    Log.d(TAG, "Screen OFF — polling paused")
                }
                Intent.ACTION_SCREEN_ON -> {
                    isScreenOn = true
                    if (isRunning) {
                        handler.post(pollRunnable)
                        Log.d(TAG, "Screen ON — polling resumed")
                    }
                }
            }
        }
    }

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!isRunning || !isScreenOn) return
            checkForegroundApp()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        registerReceiver(screenReceiver, filter)
        isScreenOn = powerManager?.isInteractive ?: true
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
                lastForegroundPackage = null
                pauseShowing = false
                if (isScreenOn) {
                    handler.post(pollRunnable)
                }
                Log.d(TAG, "Service started")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(pollRunnable)
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        Log.d(TAG, "Service destroyed")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification ──

    private fun startForegroundWithNotification() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Мониторинг приложений",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Mindful Pause отслеживает запуск приложений"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
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

        val stopIntent = Intent(this, AppMonitorService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet())?.size ?: 0

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Mindful Pause")
            .setContentText("Защита активна · Приложений: $monitored")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .addAction(Notification.Action.Builder(null, "Выключить", stopPendingIntent).build())
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    // ── Мониторинг ──

    private fun checkForegroundApp() {
        val currentPackage = getForegroundPackage() ?: return

        // Игнорируем системные и наши пакеты
        if (IGNORED_PACKAGES.any { currentPackage.startsWith(it) }) {
            // Если ушли из PauseActivity — сбрасываем флаг
            if (pauseShowing && currentPackage != packageName) {
                pauseShowing = false
            }
            return
        }

        // PauseActivity на экране — не реагируем
        if (currentPackage == packageName) {
            pauseShowing = true
            return
        }

        // Только что ушли из PauseActivity — даём 1.5 сек на запись cooldown
        if (pauseShowing) {
            pauseShowing = false
            pauseDismissedAt = System.currentTimeMillis()
            return
        }
        if (System.currentTimeMillis() - pauseDismissedAt < 1500) {
            return
        }

        // Если foreground не изменился — ничего не делаем
        if (currentPackage == lastForegroundPackage) return
        lastForegroundPackage = currentPackage

        // Проверяем, есть ли пакет в отслеживаемых
        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()
        if (currentPackage !in monitored) return

        // Проверяем установлено ли приложение
        if (!isPackageInstalled(currentPackage)) {
            Log.d(TAG, "$currentPackage uninstalled — removing")
            prefs.edit().putStringSet(KEY_MONITORED,
                monitored.toMutableSet().apply { remove(currentPackage) }
            ).apply()
            return
        }

        // Проверяем cooldown (читаем из SharedPreferences, куда пишет PauseActivity)
        val cooldownMs = getCooldownMs()
        val now = System.currentTimeMillis()
        val lastProceed = prefs.getLong(KEY_COOLDOWN_PREFIX + currentPackage, 0L)
        if (now - lastProceed < cooldownMs) {
            val remaining = (cooldownMs - (now - lastProceed)) / 1000
            Log.d(TAG, "Cooldown active for $currentPackage (${remaining}s left)")
            return
        }

        // Показываем паузу
        Log.d(TAG, "Intercepted: $currentPackage → showing pause")
        pauseShowing = true
        showPauseOverlay(currentPackage)
    }

    private fun getForegroundPackage(): String? {
        val now = System.currentTimeMillis()
        val stats = usageStatsManager?.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 10_000,
            now
        )
        if (stats.isNullOrEmpty()) return null
        return stats.maxByOrNull { it.lastTimeUsed }?.packageName
    }

    private fun getCooldownMs(): Long {
        val minutes = prefs.getInt(KEY_COOLDOWN_MINUTES, 5)
        return minutes * 60 * 1000L
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getApplicationInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun showPauseOverlay(targetPackage: String) {
        val appName = try {
            val appInfo = packageManager.getApplicationInfo(targetPackage, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) {
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