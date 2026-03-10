package com.example.mindfull

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.ContentValues
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
        private const val KEY_REMAINING_MS = "remaining_ms"
        private const val KEY_NOTE_TEXT = "note_text"

        // Дыхательный цикл: вдох 4с → задержка 2с → выдох 4с = 10с
        private const val INHALE_MS = 4_000L
        private const val HOLD_MS = 2_000L
        private const val EXHALE_MS = 4_000L
    }

    private lateinit var tvTimer: TextView
    private lateinit var tvBreathHint: TextView
    private lateinit var breathCircle: View
    private lateinit var btnProceed: MaterialButton
    private lateinit var etNote: TextInputEditText

    private var targetPackage: String = ""
    private var appName: String = ""
    private var timer: CountDownTimer? = null
    private var breathAnimator: AnimatorSet? = null
    private var remainingMs: Long = TIMER_DURATION_MS
    private var timerFinished = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_pause)

        targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE) ?: ""
        appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "приложение"

        tvTimer = findViewById(R.id.tvTimer)
        tvBreathHint = findViewById(R.id.tvBreathHint)
        breathCircle = findViewById(R.id.breathCircle)
        btnProceed = findViewById(R.id.btnProceed)
        etNote = findViewById(R.id.etNote)

        // Восстанавливаем состояние после rotation
        if (savedInstanceState != null) {
            remainingMs = savedInstanceState.getLong(KEY_REMAINING_MS, TIMER_DURATION_MS)
            val savedNote = savedInstanceState.getString(KEY_NOTE_TEXT, "")
            etNote.setText(savedNote)
        }

        timerFinished = remainingMs <= 0

        if (timerFinished) {
            activateButton()
            tvTimer.text = "0"
        } else {
            btnProceed.text = "Подожди..."
            btnProceed.isEnabled = false
            startTimer(remainingMs)
        }

        startBreathAnimation()

        btnProceed.setOnClickListener {
            saveNoteAndProceed()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putLong(KEY_REMAINING_MS, remainingMs)
        outState.putString(KEY_NOTE_TEXT, etNote.text?.toString() ?: "")
    }

    override fun onDestroy() {
        timer?.cancel()
        breathAnimator?.cancel()
        super.onDestroy()
    }

    // Запрет кнопки "Назад" пока таймер идёт.
    // Если таймер истёк — back просто закрывает без перехода в целевое приложение.
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!timerFinished) {
            // Таймер ещё идёт — игнорируем
            return
        }
        // Таймер закончен — позволяем закрыть (без перехода в целевое приложение)
        finish()
    }

    // ── Таймер ──

    private fun startTimer(durationMs: Long) {
        timer?.cancel()
        timer = object : CountDownTimer(durationMs, TICK_INTERVAL_MS) {
            override fun onTick(millisLeft: Long) {
                remainingMs = millisLeft
                val seconds = (millisLeft / 1000).toInt()
                tvTimer.text = seconds.toString()
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

        btnProceed.alpha = 0.7f
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
        val inhaleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.0f, 1.3f).apply {
            duration = INHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.0f, 1.3f).apply {
            duration = INHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }

        val hold = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = HOLD_MS
        }

        val exhaleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.3f, 1.0f).apply {
            duration = EXHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.3f, 1.0f).apply {
            duration = EXHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }

        inhaleX.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Вдох..."
        }
        hold.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Задержка..."
        }
        exhaleX.addUpdateListener {
            if (it.animatedFraction < 0.05f) tvBreathHint.text = "Выдох..."
        }

        val inhaleSet = AnimatorSet().apply { playTogether(inhaleX, inhaleY) }
        val exhaleSet = AnimatorSet().apply { playTogether(exhaleX, exhaleY) }

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

    // ── Сохранение заметки и переход ──

    private fun saveNoteAndProceed() {
        val noteText = etNote.text?.toString()?.trim() ?: ""

        if (noteText.isNotEmpty()) {
            saveNote(noteText)
        }

        // Открываем целевое приложение
        if (targetPackage.isNotEmpty()) {
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

        finish()
    }

    private fun saveNote(text: String) {
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
            android.util.Log.e("PauseActivity", "Failed to save note", e)
        }
    }
}