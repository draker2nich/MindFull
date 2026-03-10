package com.example.mindfull

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.ContentValues
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
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

        btnProceed.text = "Подожди..."
        btnProceed.isEnabled = false

        btnProceed.setOnClickListener {
            saveNoteAndProceed()
        }

        startTimer()
        startBreathAnimation()
    }

    override fun onDestroy() {
        timer?.cancel()
        breathAnimator?.cancel()
        super.onDestroy()
    }

    // Запрет кнопки "Назад" пока таймер идёт
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!btnProceed.isEnabled) {
            // Игнорируем — таймер ещё идёт
            return
        }
        super.onBackPressed()
    }

    // ── Таймер ──

    private fun startTimer() {
        timer = object : CountDownTimer(TIMER_DURATION_MS, TICK_INTERVAL_MS) {
            override fun onTick(millisLeft: Long) {
                val seconds = (millisLeft / 1000).toInt()
                tvTimer.text = seconds.toString()
            }

            override fun onFinish() {
                tvTimer.text = "0"
                activateButton()
            }
        }.start()
    }

    private fun activateButton() {
        btnProceed.isEnabled = true
        btnProceed.text = "Открыть $appName"

        // Плавное появление
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
        // Вдох: масштаб 1.0 → 1.3
        val inhaleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.0f, 1.3f).apply {
            duration = INHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }
        val inhaleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.0f, 1.3f).apply {
            duration = INHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }

        // Задержка: остаётся на 1.3 (используем ValueAnimator как delay)
        val hold = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = HOLD_MS
        }

        // Выдох: масштаб 1.3 → 1.0
        val exhaleX = ObjectAnimator.ofFloat(breathCircle, "scaleX", 1.3f, 1.0f).apply {
            duration = EXHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }
        val exhaleY = ObjectAnimator.ofFloat(breathCircle, "scaleY", 1.3f, 1.0f).apply {
            duration = EXHALE_MS
            interpolator = AccelerateDecelerateInterpolator()
        }

        // Обновляем текст подсказки
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
                    // Зацикливаем, если activity ещё жива
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
            val launchIntent = packageManager.getLaunchIntentForPackage(targetPackage)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
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