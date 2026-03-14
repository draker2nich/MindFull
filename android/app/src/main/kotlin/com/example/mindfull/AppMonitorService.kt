package com.example.mindfull

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
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

/**
 * Сервис мониторинга foreground-приложений.
 *
 * Каждые 500мс читает UsageEvents и определяет текущий foreground-пакет.
 * Для каждого отслеживаемого пакета ведёт независимую state-machine.
 *
 * STATE MACHINE (per-package):
 *
 *   IDLE ──(enters foreground)──→ проверка cooldown
 *           │                       │
 *           │              cooldown active → ACCESS_GRANTED
 *           │              cooldown нет    → PAUSE_SHOWING (запуск PauseActivity)
 *           │
 *   PAUSE_SHOWING ──(leaves without confirm)──→ IDLE
 *                  ──(confirmation consumed)──→ ACCESS_GRANTED
 *
 *   ACCESS_GRANTED ──(leaves foreground)──→ IDLE
 *
 * "Leaves foreground" = другой НЕ-наш пакет стал foreground, или экран выключился.
 * Переход на наш пакет (PauseActivity) НЕ считается уходом.
 *
 * hasLeftForeground map отслеживает уход пользователя из каждого пакета,
 * чтобы отличить внутреннюю навигацию (повторный resumed без ухода)
 * от реального повторного входа (resumed после ухода).
 */
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
        private const val KEY_COOLDOWN_ENABLED = "cooldown_enabled"
        private const val KEY_COOLDOWN_PREFIX = "cooldown_"

        const val KEY_PAUSE_CONFIRMED_PACKAGE = "pause_confirmed_package"
        const val KEY_PAUSE_CONFIRMED_AT = "pause_confirmed_at"

        @Volatile
        var isRunning = false
            private set

        fun updateMonitoredPackages(ctx: Context, packages: List<String>) {
            val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(KEY_MONITORED, packages.toSet()).apply()
            Log.d(TAG, "Updated monitored packages: $packages")
        }
    }

    private enum class AppState {
        IDLE,
        PAUSE_SHOWING,
        ACCESS_GRANTED,
    }

    private val handler = Handler(Looper.getMainLooper())
    private var usageStatsManager: UsageStatsManager? = null
    private lateinit var prefs: SharedPreferences
    private var powerManager: PowerManager? = null
    private var isScreenOn = true

    private val appStates = mutableMapOf<String, AppState>()
    private var lastProcessedEventTime: Long = 0
    private var currentForeground: String? = null

    /**
     * Отслеживает, уходил ли пользователь из каждого пакета.
     * true = пакет уходил с foreground → следующий resumed = новый вход.
     * false = пакет на foreground непрерывно → resumed = навигация внутри.
     * default true для первого входа.
     */
    private val hasLeftForeground = mutableMapOf<String, Boolean>()

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOn = false
                    handler.removeCallbacks(pollRunnable)
                    resetAllStates()
                    Log.d(TAG, "Screen OFF — all states reset")
                }
                Intent.ACTION_SCREEN_ON -> {
                    isScreenOn = true
                    if (isRunning) {
                        lastProcessedEventTime = System.currentTimeMillis()
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
            try {
                poll()
            } catch (e: Exception) {
                Log.e(TAG, "Poll error", e)
            }
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
                Log.d(TAG, "Service stopped")
                return START_NOT_STICKY
            }
            else -> {
                startForegroundWithNotification()
                isRunning = true
                appStates.clear()
                hasLeftForeground.clear()
                currentForeground = null
                lastProcessedEventTime = System.currentTimeMillis()
                clearPauseConfirmation()
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
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ══════════════════════════════════════════════════════════
    //  CORE POLLING
    // ══════════════════════════════════════════════════════════

    private fun poll() {
        consumePauseConfirmation()
        val transitions = collectResumedEvents()
        for (pkg in transitions) {
            processResumedEvent(pkg)
        }
    }

    private fun collectResumedEvents(): List<String> {
        val now = System.currentTimeMillis()
        val start = if (lastProcessedEventTime > 0) lastProcessedEventTime else now - 3000

        val usageEvents = usageStatsManager?.queryEvents(start, now) ?: return emptyList()

        val result = mutableListOf<String>()
        val event = UsageEvents.Event()
        var maxTime = lastProcessedEventTime

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED &&
                event.timeStamp > lastProcessedEventTime
            ) {
                result.add(event.packageName)
                if (event.timeStamp > maxTime) maxTime = event.timeStamp
            }
        }

        if (maxTime > lastProcessedEventTime) {
            lastProcessedEventTime = maxTime
        }

        return result
    }

    // ══════════════════════════════════════════════════════════
    //  PER-EVENT PROCESSING
    // ══════════════════════════════════════════════════════════

    private fun processResumedEvent(pkg: String) {
        val prevForeground = currentForeground

        // ── Наш пакет (PauseActivity / MainActivity) ──
        if (isOurPackage(pkg)) {
            currentForeground = pkg
            return
        }

        // ── Чужой пакет стал foreground ──
        currentForeground = pkg
        val comingFromOurPkg = prevForeground != null && isOurPackage(prevForeground)

        // Все отслеживаемые пакеты кроме текущего: помечаем как ушедшие, сбрасываем в IDLE
        for ((trackedPkg, state) in appStates.entries.toList()) {
            if (trackedPkg != pkg && state != AppState.IDLE) {
                Log.d(TAG, "[$trackedPkg] User left (fg now $pkg) → IDLE (was $state)")
                appStates[trackedPkg] = AppState.IDLE
                hasLeftForeground[trackedPkg] = true
            }
        }

        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()

        if (pkg !in monitored) {
            // Не отслеживаемый — помечаем все отслеживаемые как ушедшие
            for (trackedPkg in monitored) {
                if (appStates.getOrDefault(trackedPkg, AppState.IDLE) != AppState.IDLE) {
                    appStates[trackedPkg] = AppState.IDLE
                }
                hasLeftForeground[trackedPkg] = true
            }
            return
        }

        // ── pkg — отслеживаемый пакет ──
        handleMonitoredAppForeground(pkg, comingFromOurPkg, prevForeground)
    }

    private fun handleMonitoredAppForeground(
        pkg: String,
        comingFromOurPkg: Boolean,
        prevForeground: String?
    ) {
        consumePauseConfirmation()

        val state = appStates.getOrDefault(pkg, AppState.IDLE)
        val leftBefore = hasLeftForeground.getOrDefault(pkg, true)

        when (state) {
            AppState.ACCESS_GRANTED -> {
                if (comingFromOurPkg) {
                    Log.d(TAG, "[$pkg] ACCESS_GRANTED, from PauseActivity → allow")
                    return
                }
                if (!leftBefore) {
                    Log.d(TAG, "[$pkg] ACCESS_GRANTED, same session → allow")
                    return
                }
                Log.d(TAG, "[$pkg] ACCESS_GRANTED but user had left → IDLE, new entry")
                appStates[pkg] = AppState.IDLE
                hasLeftForeground[pkg] = false
                handleNewEntry(pkg)
            }

            AppState.PAUSE_SHOWING -> {
                if (comingFromOurPkg) {
                    consumePauseConfirmation()
                    val updated = appStates.getOrDefault(pkg, AppState.IDLE)
                    if (updated == AppState.ACCESS_GRANTED) {
                        Log.d(TAG, "[$pkg] Confirmed via PauseActivity → access granted")
                        hasLeftForeground[pkg] = false
                        return
                    }
                    Log.d(TAG, "[$pkg] PAUSE_SHOWING, from PauseActivity but NO confirm → reset")
                    appStates[pkg] = AppState.IDLE
                    hasLeftForeground[pkg] = false
                    handleNewEntry(pkg)
                    return
                }
                Log.d(TAG, "[$pkg] PAUSE_SHOWING, from ${prevForeground ?: "null"} → reset, new pause")
                appStates[pkg] = AppState.IDLE
                hasLeftForeground[pkg] = false
                handleNewEntry(pkg)
            }

            AppState.IDLE -> {
                if (!leftBefore && prevForeground == pkg) {
                    Log.d(TAG, "[$pkg] IDLE, same foreground without leave → skip")
                    return
                }
                hasLeftForeground[pkg] = false
                handleNewEntry(pkg)
            }
        }
    }

    private fun handleNewEntry(pkg: String) {
        if (!isPackageInstalled(pkg)) {
            Log.d(TAG, "[$pkg] Not installed — removing from monitored")
            val m = prefs.getStringSet(KEY_MONITORED, emptySet())?.toMutableSet() ?: mutableSetOf()
            m.remove(pkg)
            prefs.edit().putStringSet(KEY_MONITORED, m).apply()
            return
        }

        val cooldownEnabled = prefs.getBoolean(KEY_COOLDOWN_ENABLED, true)
        if (cooldownEnabled) {
            val cooldownMs = getCooldownMs()
            val now = System.currentTimeMillis()
            val lastConfirm = prefs.getLong(KEY_COOLDOWN_PREFIX + pkg, 0L)
            if (cooldownMs > 0 && lastConfirm > 0 && now - lastConfirm < cooldownMs) {
                val rem = (cooldownMs - (now - lastConfirm)) / 1000
                Log.d(TAG, "[$pkg] Cooldown active (${rem}s left) → auto-grant")
                appStates[pkg] = AppState.ACCESS_GRANTED
                return
            }
        }

        Log.d(TAG, "[$pkg] >>> SHOWING PAUSE <<<")
        appStates[pkg] = AppState.PAUSE_SHOWING
        showPauseOverlay(pkg)
    }

    // ══════════════════════════════════════════════════════════
    //  PAUSE CONFIRMATION
    // ══════════════════════════════════════════════════════════

    private fun consumePauseConfirmation() {
        val confirmedPkg = prefs.getString(KEY_PAUSE_CONFIRMED_PACKAGE, null) ?: return
        val confirmedAt = prefs.getLong(KEY_PAUSE_CONFIRMED_AT, 0L)
        val now = System.currentTimeMillis()

        if (now - confirmedAt > 30_000) {
            clearPauseConfirmation()
            return
        }

        Log.d(TAG, "[$confirmedPkg] ✓ Confirmation consumed")
        appStates[confirmedPkg] = AppState.ACCESS_GRANTED
        clearPauseConfirmation()
    }

    private fun clearPauseConfirmation() {
        prefs.edit()
            .remove(KEY_PAUSE_CONFIRMED_PACKAGE)
            .remove(KEY_PAUSE_CONFIRMED_AT)
            .apply()
    }

    // ══════════════════════════════════════════════════════════
    //  HELPERS
    // ══════════════════════════════════════════════════════════

    private fun resetAllStates() {
        for (key in appStates.keys.toList()) {
            appStates[key] = AppState.IDLE
        }
        val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()
        for (pkg in monitored) {
            hasLeftForeground[pkg] = true
        }
        for (key in hasLeftForeground.keys.toList()) {
            hasLeftForeground[key] = true
        }
        currentForeground = null
    }

    private fun isOurPackage(pkg: String): Boolean = pkg == packageName

    private fun getCooldownMs(): Long {
        val minutes = prefs.getInt(KEY_COOLDOWN_MINUTES, 5)
        return minutes * 60 * 1000L
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getApplicationInfo(pkg, 0)
            true
        } catch (_: Exception) { false }
    }

    private fun showPauseOverlay(targetPackage: String) {
        val appName = try {
            val appInfo = packageManager.getApplicationInfo(targetPackage, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (_: Exception) { targetPackage }

        val intent = Intent(this, PauseActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(PauseActivity.EXTRA_TARGET_PACKAGE, targetPackage)
            putExtra(PauseActivity.EXTRA_APP_NAME, appName)
        }
        startActivity(intent)
    }

    // ══════════════════════════════════════════════════════════
    //  NOTIFICATION
    // ══════════════════════════════════════════════════════════

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
}