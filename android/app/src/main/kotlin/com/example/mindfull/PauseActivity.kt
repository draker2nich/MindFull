package com.example.mindfull

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.CountDownTimer
import android.util.Log
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText

/**
 * Экран паузы. Показывается поверх целевого приложения.
 *
 * Поддерживает повторные вызовы через onNewIntent:
 * - Если сервис показывает паузу для appA, а потом для appB —
 *   PauseActivity полностью сбрасывается (таймер, анимация, заметка, флаги)
 *   и начинает заново для appB.
 * - Если сервис показывает паузу повторно для того же appA —
 *   то же самое: полный сброс, таймер с начала.
 *
 * Жизненный цикл:
 * - onCreate / onNewIntent → initSession(): запускает таймер (60с) и дыхательную анимацию
 * - Пользователь ждёт окончания таймера → появляется кнопка "Открыть [app]"
 * - Нажатие кнопки → записывает confirmation + cooldown → запускает target → finish()
 * - Если пользователь ушёл без нажатия → ничего не записываем, сервис покажет заново
 *
 * ВАЖНО: confirmation записывается СИНХРОННО (commit) чтобы сервис
 * гарантированно прочитал его при следующем poll'е.
 */
class PauseActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_TARGET_PACKAGE = "target_package"
        const val EXTRA_APP_NAME = "app_name"

        private const val TAG = "PauseActivity"
        private const val TIMER_DURATION_MS = 60_000L
        private const val TICK_INTERVAL_MS = 1_000L

        private const val INHALE_MS = 4_000L
        private const val HOLD_MS = 2_000L
        private const val EXHALE_MS = 4_000L

        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_COOLDOWN_PREFIX = "cooldown_"
        private const val KEY_COOLDOWN_ENABLED = "cooldown_enabled"
    }

    private lateinit var tvTimer: TextView
    private lateinit var tvBreathHint: TextView
    private lateinit var breathCircle: View
    private lateinit var breathGlow: View
    private lateinit var btnProceed: MaterialButton
    private lateinit var etNote: TextInputEditText
    private var tvSubtitle: TextView? = null

    private var targetPackage: String = ""
    private var appName: String = ""
    private var timer: CountDownTimer? = null
    private var breathAnimator: AnimatorSet? = null
    private var timerFinished = false
    private var didProceedToApp = false
    private var noteSaved = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pause)

        tvTimer = findViewById(R.id.tvTimer)
        tvBreathHint = findViewById(R.id.tvBreathHint)
        breathCircle = findViewById(R.id.breathCircle)
        breathGlow = findViewById(R.id.breathGlow)
        btnProceed = findViewById(R.id.btnProceed)
        etNote = findViewById(R.id.etNote)
        tvSubtitle = findViewById(R.id.tvSubtitle)

        btnProceed.setOnClickListener {
            onProceedClicked()
        }

        initSession(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.d(TAG, "onNewIntent — resetting session")

        // Сохраняем заметку предыдущей сессии если есть
        saveNoteOnce()

        // Полный сброс для новой сессии
        initSession(intent)
    }

    /**
     * Инициализирует (или полностью переинициализирует) сессию паузы.
     * Вызывается из onCreate и onNewIntent.
     */
    private fun initSession(intent: Intent) {
        // Останавливаем предыдущий таймер и анимацию
        timer?.cancel()
        timer = null
        breathAnimator?.cancel()
        breathAnimator = null

        // Сбрасываем все флаги
        timerFinished = false
        didProceedToApp = false
        noteSaved = false

        // Читаем данные из intent
        targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE) ?: ""
        appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "приложение"

        Log.d(TAG, "initSession for: $targetPackage ($appName)")

        // Сбрасываем UI
        tvSubtitle?.text = "Перед открытием $appName"
        etNote.setText("")
        tvTimer.text = (TIMER_DURATION_MS / 1000).toString()
        tvBreathHint.text = "Вдох..."

        btnProceed.text = "Подожди..."
        btnProceed.isEnabled = false
        btnProceed.alpha = 0.5f

        // Сбрасываем scale/alpha анимаций дыхания к начальным значениям
        breathCircle.scaleX = 1.0f
        breathCircle.scaleY = 1.0f
        breathGlow.scaleX = 1.0f
        breathGlow.scaleY = 1.0f
        breathGlow.alpha = 0.4f

        // Запускаем заново
        startTimer(TIMER_DURATION_MS)
        startBreathAnimation()
    }

    private fun onProceedClicked() {
        if (didProceedToApp) return
        didProceedToApp = true

        Log.d(TAG, "User clicked Proceed for: $targetPackage")

        saveNoteOnce()

        // 1. Записываем confirmation СИНХРОННО
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()

        editor.putString(AppMonitorService.KEY_PAUSE_CONFIRMED_PACKAGE, targetPackage)
        editor.putLong(AppMonitorService.KEY_PAUSE_CONFIRMED_AT, System.currentTimeMillis())

        // 2. Если cooldown включён — записываем cooldown timestamp
        val cooldownEnabled = prefs.getBoolean(KEY_COOLDOWN_ENABLED, true)
        if (cooldownEnabled) {
            editor.putLong(KEY_COOLDOWN_PREFIX + targetPackage, System.currentTimeMillis())
            Log.d(TAG, "Cooldown timestamp set for $targetPackage")
        }

        editor.commit()

        // 3. Запускаем целевое приложение
        launchTargetApp()

        // 4. Закрываем PauseActivity
        finish()
    }

    override fun onPause() {
        super.onPause()
        if (!didProceedToApp) {
            saveNoteOnce()
            Log.d(TAG, "onPause without proceed — pause will reset on next entry")
        }
    }

    override fun onDestroy() {
        timer?.cancel()
        breathAnimator?.cancel()
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!timerFinished) return
        saveNoteOnce()
        finish()
    }

    // ── Таймер ──

    private fun startTimer(durationMs: Long) {
        timer?.cancel()
        timer = object : CountDownTimer(durationMs, TICK_INTERVAL_MS) {
            override fun onTick(millisLeft: Long) {
                tvTimer.text = (millisLeft / 1000).toInt().toString()
            }

            override fun onFinish() {
                timerFinished = true
                tvTimer.text = "0"
                activateButton()
            }
        }.start()
    }

    private fun activateButton() {
        btnProceed.isEnabled = true
        btnProceed.text = "Открыть $appName"
        btnProceed.animate()
            .alpha(1f)
            .setDuration(400)
            .start()
    }

    // ── Дыхательная анимация ──

    private fun startBreathAnimation() {
        runBreathCycle()
    }

    private fun runBreathCycle() {
        val inhaleCircleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.0f, 1.25f).apply {
            duration = INHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleCircleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.0f, 1.25f).apply {
            duration = INHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleGlowX = ObjectAnimator.ofFloat(breathGlow, "scaleX", 1.0f, 1.4f).apply {
            duration = INHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleGlowY = ObjectAnimator.ofFloat(breathGlow, "scaleY", 1.0f, 1.4f).apply {
            duration = INHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleGlowAlpha = ObjectAnimator.ofFloat(breathGlow, "alpha", 0.4f, 0.8f).apply {
            duration = INHALE_MS
        }

        val hold = ValueAnimator.ofFloat(0f, 1f).apply { duration = HOLD_MS }

        val exhaleCircleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.25f, 1.0f).apply {
            duration = EXHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleCircleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.25f, 1.0f).apply {
            duration = EXHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleGlowX = ObjectAnimator.ofFloat(breathGlow, "scaleX", 1.4f, 1.0f).apply {
            duration = EXHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleGlowY = ObjectAnimator.ofFloat(breathGlow, "scaleY", 1.4f, 1.0f).apply {
            duration = EXHALE_MS; interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleGlowAlpha = ObjectAnimator.ofFloat(breathGlow, "alpha", 0.8f, 0.4f).apply {
            duration = EXHALE_MS
        }

        inhaleCircleX.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Вдох..."
        }
        hold.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Задержка..."
        }
        exhaleCircleX.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Выдох..."
        }

        val inhaleSet = AnimatorSet().apply {
            playTogether(inhaleCircleX, inhaleCircleY, inhaleGlowX, inhaleGlowY, inhaleGlowAlpha)
        }
        val exhaleSet = AnimatorSet().apply {
            playTogether(exhaleCircleX, exhaleCircleY, exhaleGlowX, exhaleGlowY, exhaleGlowAlpha)
        }

        breathAnimator = AnimatorSet().apply {
            playSequentially(inhaleSet, hold, exhaleSet)
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (!isFinishing && !isDestroyed) {
                        runBreathCycle()
                    }
                }
            })
            start()
        }
    }

    // ── Заметка ──

    private fun saveNoteOnce() {
        if (noteSaved) return
        val text = etNote.text?.toString()?.trim() ?: ""
        if (text.isEmpty()) return
        noteSaved = true

        try {
            val db = NoteDbHelper(this).writableDatabase
            val values = ContentValues().apply {
                put(NoteDbHelper.COL_TEXT, text)
                put(NoteDbHelper.COL_APP_PACKAGE, targetPackage)
                put(NoteDbHelper.COL_APP_NAME, appName)
                put(NoteDbHelper.COL_TIMESTAMP, System.currentTimeMillis())
            }
            db.insert(NoteDbHelper.TABLE_NAME, null, values)
            db.close()
        } catch (e: Exception) {
            noteSaved = false
            Log.e(TAG, "Failed to save note", e)
        }
    }

    // ── Запуск целевого приложения ──

    private fun launchTargetApp() {
        if (targetPackage.isEmpty()) return
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch $targetPackage", e)
        }
    }
}