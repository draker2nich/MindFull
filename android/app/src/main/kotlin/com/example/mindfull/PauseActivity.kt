package com.example.mindfull

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.CountDownTimer
import android.view.View
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText

class PauseActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_TARGET_PACKAGE = "target_package"
        const val EXTRA_APP_NAME = "app_name"

        private const val TIMER_DURATION_MS = 60_000L
        private const val TICK_INTERVAL_MS = 1_000L

        private const val INHALE_MS = 4_000L
        private const val HOLD_MS = 2_000L
        private const val EXHALE_MS = 4_000L

        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_COOLDOWN_PREFIX = "cooldown_"
    }

    private lateinit var tvTimer: TextView
    private lateinit var tvBreathHint: TextView
    private lateinit var breathCircle: View
    private lateinit var breathGlow: View
    private lateinit var btnProceed: MaterialButton
    private lateinit var etNote: TextInputEditText

    private var targetPackage: String = ""
    private var appName: String = ""
    private var timer: CountDownTimer? = null
    private var breathAnimator: AnimatorSet? = null
    private var remainingMs: Long = TIMER_DURATION_MS
    private var timerFinished = false
    private var didProceedToApp = false
    private var noteSaved = false // Защита от двойного сохранения

    // configChanges="orientation|screenSize|keyboardHidden" в манифесте
    // значит onCreate вызывается 1 раз, rotation обрабатывается без пересоздания.
    // savedInstanceState не нужен — таймер продолжает работать.

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pause)

        targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE) ?: ""
        appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "приложение"

        tvTimer = findViewById(R.id.tvTimer)
        tvBreathHint = findViewById(R.id.tvBreathHint)
        breathCircle = findViewById(R.id.breathCircle)
        breathGlow = findViewById(R.id.breathGlow)
        btnProceed = findViewById(R.id.btnProceed)
        etNote = findViewById(R.id.etNote)

        findViewById<TextView>(R.id.tvSubtitle)?.text = "Перед открытием $appName"

        btnProceed.text = "Подожди..."
        btnProceed.isEnabled = false
        btnProceed.alpha = 0.5f

        startTimer(TIMER_DURATION_MS)
        startBreathAnimation()

        btnProceed.setOnClickListener {
            didProceedToApp = true
            saveNoteOnce()
            setCooldownForPackage(targetPackage)
            launchTargetApp()
            finish()
        }
    }

    override fun onPause() {
        super.onPause()
        // Если свернул без нажатия "Открыть" — сохраняем заметку, но НЕ cooldown
        if (!didProceedToApp) {
            saveNoteOnce()
        }
    }

    override fun onDestroy() {
        timer?.cancel()
        breathAnimator?.cancel()
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
                remainingMs = millisLeft
                tvTimer.text = (millisLeft / 1000).toInt().toString()
            }

            override fun onFinish() {
                remainingMs = 0
                timerFinished = true
                tvTimer.text = "0"
                activateButton()
            }
        }.start()
    }

    private fun activateButton() {
        timerFinished = true
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

    // ── Заметка (с защитой от двойного сохранения) ──

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
            noteSaved = false // Позволяем повторную попытку при ошибке
            android.util.Log.e("PauseActivity", "Failed to save note", e)
        }
    }

    // ── Cooldown ──

    private fun setCooldownForPackage(pkg: String) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putLong(KEY_COOLDOWN_PREFIX + pkg, System.currentTimeMillis()).apply()
    }

    // ── Переход в целевое приложение ──

    private fun launchTargetApp() {
        if (targetPackage.isEmpty()) return
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
            }
        } catch (e: Exception) {
            android.util.Log.e("PauseActivity", "Failed to launch $targetPackage", e)
        }
    }
}