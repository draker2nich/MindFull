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
 * Каждые 500мс читает UsageEvents и обрабатывает каждый ACTIVITY_RESUMED
 * в хронологическом порядке. Для каждого отслеживаемого пакета ведёт
 * независимую state-machine.
 *
 * STATE MACHINE (per-package):
 *
 *   IDLE ──(foreground)──→ проверка cooldown
 *           │                 │
 *           │        cooldown active → ACCESS_GRANTED
 *           │        cooldown нет    → PAUSE_SHOWING (запуск PauseActivity)
 *           │
 *   PAUSE_SHOWING ──(user leaves to non-our pkg)──→ IDLE
 *                  ──(user leaves to our pkg)──→ stay PAUSE_SHOWING
 *                  ──(confirmation consumed)──→ ACCESS_GRANTED
 *
 *   ACCESS_GRANTED ──(user leaves to non-our pkg)──→ IDLE
 *                   ──(user leaves to our pkg)──→ stay ACCESS_GRANTED
 *
 * "User leaves" = другой пакет стал foreground.
 * "Our pkg" = com.example.mindfull (PauseActivity / MainActivity).
 * Переход на наш пакет НЕ сбрасывает state целевого приложения,
 * потому что PauseActivity — часть паузы для этого приложения.
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

        fun updateMonitoredPackages(context: Context, packages: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(KEY_MONITORED, packages.toSet()).apply()
            Log.d(TAG, "Updated monitored packages: $packages")
        }
    }

    private enum class AppState {
        /** Нет активной сессии. При новом входе — проверяем cooldown, показываем паузу. */
        IDLE,
        /** PauseActivity показывается для этого пакета. */
        PAUSE_SHOWING,
        /** Пользователь нажал "Открыть" — доступ выдан. */
        ACCESS_GRANTED,
    }

    private val handler = Handler(Looper.getMainLooper())
    private var usageStatsManager: UsageStatsManager? = null
    private lateinit var prefs: SharedPreferences
    private var powerManager: PowerManager? = null
    private var isScreenOn = true

    /** Независимое состояние для каждого отслеживаемого пакета */
    private val appStates = mutableMapOf<String, AppState>()

    /** Timestamp последнего обработанного UsageEvent */
    private var lastProcessedEventTime: Long = 0

    /**
     * Пакет, который СЕЙЧАС на переднем плане.
     * Обновляется при каждом ACTIVITY_RESUMED.
     * Используется чтобы определить "уход" — когда другой пакет стал foreground,
     * все отслеживаемые пакеты (кроме нового) у которых state != IDLE → сбрасываются.
     */
    private var currentForeground: String? = null

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
        // 1. Проверяем подтверждение от PauseActivity
        consumePauseConfirmation()

        // 2. Читаем ВСЕ ACTIVITY_RESUMED события с прошлого poll'а
        val transitions = collectResumedEvents()

        // 3. Обрабатываем каждый переход последовательно
        for (pkg in transitions) {
            processResumedEvent(pkg)
        }
    }

    /**
     * Возвращает хронологический список пакетов из ACTIVITY_RESUMED событий
     * с момента последнего вызова. Если A→B→A между poll'ами → [A, B, A].
     */
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
                event.timeStamp > lastProcessedEventTime) {
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

    /**
     * Обрабатывает один ACTIVITY_RESUMED для пакета [pkg].
     *
     * Логика:
     * 1. Если pkg == наш пакет → запоминаем currentForeground, не трогаем states
     * 2. Если pkg != currentForeground (смена foreground на ЧУЖОЙ пакет):
     *    a) Все отслеживаемые пакеты в состоянии PAUSE_SHOWING или ACCESS_GRANTED,
     *       кроме pkg, сбрасываем в IDLE (пользователь ушёл из них)
     *    b) Если pkg — отслеживаемый → обрабатываем вход
     * 3. Если pkg == currentForeground → ничего (тот же пакет, повторный resumed)
     */
    private fun processResumedEvent(pkg: String) {
        // ── Наш пакет (PauseActivity / MainActivity) ──
        if (isOurPackage(pkg)) {
            currentForeground = pkg
            // НЕ сбрасываем states — PauseActivity является частью процесса паузы
            return
        }

        // ── Смена foreground на чужой пакет ──
        if (pkg != currentForeground) {
            val prev = currentForeground
            currentForeground = pkg

            // Все отслеживаемые пакеты, которые НЕ являются текущим новым foreground
            // и НЕ в IDLE — сбрасываем в IDLE.
            // Это означает: пользователь ушёл из них.
            // Исключение: если prev был наш пакет, а новый — тот же отслеживаемый,
            // к которому привязана пауза (PauseActivity → target после confirm).
            // Это обработается ниже через ACCESS_GRANTED check.
            for ((trackedPkg, state) in appStates.entries.toList()) {
                if (trackedPkg != pkg && state != AppState.IDLE) {
                    // Не сбрасываем если переход был наш_пакет → другой_отслеживаемый,
                    // потому что это нормальный flow: пользователь был в PauseActivity для appA,
                    // а потом foreground стал appB. appA надо сбросить.
                    Log.d(TAG, "[$trackedPkg] User left (fg now $pkg) → IDLE (was $state)")
                    appStates[trackedPkg] = AppState.IDLE
                }
            }

            // Для текущего pkg:
            // Если prev был наш пакет — это может быть PauseActivity → target после confirm.
            // Если prev был другой пакет — это новый вход.
            val comingFromOurPkg = prev != null && isOurPackage(prev)

            val monitored = prefs.getStringSet(KEY_MONITORED, emptySet()) ?: emptySet()
            if (pkg !in monitored) return

            handleMonitoredAppEntry(pkg, comingFromOurPkg)

        }
        // Если pkg == currentForeground — тот же пакет resumed повторно,
        // это навигация внутри приложения, не новый вход.
    }

    /**
     * Отслеживаемый пакет [pkg] стал foreground.
     * [comingFromOurPkg] = true если предыдущий foreground был наш пакет (PauseActivity).
     */
    private fun handleMonitoredAppEntry(pkg: String, comingFromOurPkg: Boolean) {
        // Перечитываем confirmation на случай если PauseActivity только что записала
        consumePauseConfirmation()

        val state = appStates.getOrDefault(pkg, AppState.IDLE)

        when (state) {
            AppState.ACCESS_GRANTED -> {
                // Доступ уже выдан (подтверждение было consumed).
                // Если мы пришли от нашего пакета — это PauseActivity → target, нормально.
                // Если пришли от другого пакета — значит пользователь ушёл и вернулся.
                // Но "ушёл" должен был сбросить state в IDLE (в цикле выше).
                // Если мы всё равно тут с ACCESS_GRANTED — значит это первый переход
                // PauseActivity → target. Пропускаем.
                Log.d(TAG, "[$pkg] ACCESS_GRANTED, comingFromOur=$comingFromOurPkg → skip pause")
                return
            }

            AppState.PAUSE_SHOWING -> {
                // Пауза была показана для этого пакета.
                if (comingFromOurPkg) {
                    // PauseActivity → target: возможно confirm, возможно back.
                    // Проверяем confirmation ещё раз.
                    consumePauseConfirmation()
                    val updated = appStates.getOrDefault(pkg, AppState.IDLE)
                    if (updated == AppState.ACCESS_GRANTED) {
                        Log.d(TAG, "[$pkg] Confirmed via PauseActivity → access granted")
                        return
                    }
                    // Не подтверждено, но пришли от нашего пакета.
                    // Это может быть: PauseActivity закрылась (back/home через наш пакет),
                    // а target стал foreground. Или PauseActivity.finish() без confirm
                    // и Android вернул target.
                    // В любом случае — пауза не была подтверждена. Сброс. Новая пауза.
                    Log.d(TAG, "[$pkg] PAUSE_SHOWING, from our pkg but NO confirm → reset, new pause")
                    appStates[pkg] = AppState.IDLE
                    handleNewEntry(pkg)
                    return
                } else {
                    // Пришли от другого стороннего пакета. Значит пользователь ушёл
                    // (свернул, переключился) и вернулся. Сброс. Новая пауза.
                    Log.d(TAG, "[$pkg] PAUSE_SHOWING, from foreign pkg → reset, new pause")
                    appStates[pkg] = AppState.IDLE
                    handleNewEntry(pkg)
                    return
                }
            }

            AppState.IDLE -> {
                // Стандартный новый вход.
                handleNewEntry(pkg)
            }
        }
    }

    /**
     * Новый вход в отслеживаемое приложение из IDLE.
     * Проверяем cooldown → показываем паузу или даём доступ.
     */
    private fun handleNewEntry(pkg: String) {
        if (!isPackageInstalled(pkg)) {
            Log.d(TAG, "[$pkg] Not installed — removing from monitored")
            val m = prefs.getStringSet(KEY_MONITORED, emptySet())?.toMutableSet() ?: mutableSetOf()
            m.remove(pkg)
            prefs.edit().putStringSet(KEY_MONITORED, m).apply()
            return
        }

        // Проверяем cooldown
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

        // Показываем паузу
        Log.d(TAG, "[$pkg] >>> SHOWING PAUSE <<<")
        appStates[pkg] = AppState.PAUSE_SHOWING
        showPauseOverlay(pkg)
    }

    // ══════════════════════════════════════════════════════════
    //  PAUSE CONFIRMATION
    // ══════════════════════════════════════════════════════════

    /**
     * Читает и потребляет подтверждение от PauseActivity.
     * PauseActivity пишет (commit) пакет + timestamp при нажатии "Открыть".
     */
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