package com.example.mindfull

import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.os.CountDownTimer
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout

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
    private lateinit var tvTitle: TextView
    private lateinit var tvSubtitle: TextView
    private lateinit var breathCircleOuter: CircleView
    private lateinit var breathCircleMiddle: CircleView
    private lateinit var breathCircleInner: CircleView
    private lateinit var btnProceed: MaterialButton
    private lateinit var etNote: TextInputEditText
    private lateinit var tilNote: TextInputLayout
    private lateinit var progressView: CircularProgressView

    private var targetPackage: String = ""
    private var appName: String = ""
    private var timer: CountDownTimer? = null
    private var breathAnimator: AnimatorSet? = null
    private var timerFinished = false
    private var didProceedToApp = false
    private var noteSaved = false

    private var accentColor = 0
    private var bgColor = 0
    private var textPrimary = 0
    private var textSecondary = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.apply {
            addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
            statusBarColor = Color.TRANSPARENT
            navigationBarColor = Color.TRANSPARENT
        }
        initColors()
        buildUI()
        initSession(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.d(TAG, "onNewIntent — resetting session")
        saveNoteOnce()
        initSession(intent)
    }

    private fun initColors() {
        val isDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
        bgColor = if (isDark) Color.parseColor("#0A0F0F") else Color.parseColor("#F5F7F5")
        textPrimary = if (isDark) Color.parseColor("#E8F0EE") else Color.parseColor("#1A2B2A")
        textSecondary = if (isDark) Color.parseColor("#7A9490") else Color.parseColor("#5E7A75")
        accentColor = if (isDark) Color.parseColor("#6EC4A8") else Color.parseColor("#4A9B80")
    }

    private fun initSession(intent: Intent) {
        timer?.cancel()
        timer = null
        breathAnimator?.cancel()
        breathAnimator = null

        timerFinished = false
        didProceedToApp = false
        noteSaved = false

        targetPackage = intent.getStringExtra(EXTRA_TARGET_PACKAGE) ?: ""
        appName = intent.getStringExtra(EXTRA_APP_NAME) ?: "приложение"
        Log.d(TAG, "initSession for: $targetPackage ($appName)")

        tvSubtitle.text = "перед открытием $appName"
        etNote.setText("")
        tvTimer.text = (TIMER_DURATION_MS / 1000).toString()
        tvBreathHint.text = "Вдох..."

        btnProceed.text = "Подожди..."
        btnProceed.isEnabled = false
        btnProceed.alpha = 0.4f

        breathCircleOuter.scaleX = 1.0f
        breathCircleOuter.scaleY = 1.0f
        breathCircleOuter.alpha = 0.2f
        breathCircleMiddle.scaleX = 1.0f
        breathCircleMiddle.scaleY = 1.0f
        breathCircleMiddle.alpha = 0.35f
        breathCircleInner.scaleX = 1.0f
        breathCircleInner.scaleY = 1.0f
        breathCircleInner.alpha = 0.7f

        progressView.setProgress(1f)

        startTimer(TIMER_DURATION_MS)
        startBreathAnimation()
    }

    // ══════════════════════════════════════════════════════════
    //  CUSTOM VIEWS — гарантированно круглые
    // ══════════════════════════════════════════════════════════

    /**
     * Простая View которая рисует залитый круг через Canvas.
     * Никаких drawable, никаких GradientDrawable — просто circle paint.
     */
    class CircleView(context: Context, private val circleColor: Int) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = circleColor
            style = Paint.Style.FILL
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val radius = minOf(cx, cy)
            canvas.drawCircle(cx, cy, radius, paint)
        }
    }

    class CircularProgressView(
        context: Context,
        private val color: Int,
        private val strokeW: Float
    ) : View(context) {

        private var progress = 1f
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = this@CircularProgressView.color
            style = Paint.Style.STROKE
            strokeWidth = strokeW
            strokeCap = Paint.Cap.ROUND
        }
        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = Color.argb(
                40,
                Color.red(this@CircularProgressView.color),
                Color.green(this@CircularProgressView.color),
                Color.blue(this@CircularProgressView.color)
            )
            style = Paint.Style.STROKE
            strokeWidth = strokeW
        }
        private val rect = RectF()

        fun setProgress(p: Float) {
            progress = p
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val pad = strokeW / 2f
            rect.set(pad, pad, width - pad, height - pad)
            canvas.drawArc(rect, 0f, 360f, false, bgPaint)
            canvas.drawArc(rect, -90f, 360f * progress, false, paint)
        }
    }

    // ══════════════════════════════════════════════════════════
    //  BUILD UI
    // ══════════════════════════════════════════════════════════

    private fun buildUI() {
        val d = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

        val root = FrameLayout(this).apply {
            setBackgroundColor(bgColor)
            fitsSystemWindows = true
            clipChildren = false
            clipToPadding = false
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            clipChildren = false
            clipToPadding = false
        }
        root.addView(content, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Top spacer
        content.addView(View(this), lp(0, (56 * d).toInt()))

        // Title
        tvTitle = TextView(this).apply {
            text = "Сделай паузу"
            setTextColor(textPrimary)
            textSize = 26f
            typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            letterSpacing = -0.03f
        }
        content.addView(tvTitle, wrapCenter())

        // Subtitle
        tvSubtitle = TextView(this).apply {
            text = "дыши и подумай"
            setTextColor(textSecondary)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, (4 * d).toInt(), 0, 0)
        }
        content.addView(tvSubtitle, wrapCenter())

        // Flex spacer
        content.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))

        // ── Breath area ──
        // Размер контейнера = outer circle * max scale (1.3) + запас
        val areaSize = (320 * d).toInt()
        val area = FrameLayout(this).apply {
            clipChildren = false
            clipToPadding = false
        }
        content.addView(area, LinearLayout.LayoutParams(areaSize, areaSize).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })

        // Outer circle — 240dp, самый бледный
        val outerSz = (240 * d).toInt()
        breathCircleOuter = CircleView(this, accentColor).apply { alpha = 0.2f }
        area.addView(breathCircleOuter, FrameLayout.LayoutParams(outerSz, outerSz, Gravity.CENTER))

        // Middle circle — 190dp
        val midSz = (190 * d).toInt()
        breathCircleMiddle = CircleView(this, accentColor).apply { alpha = 0.35f }
        area.addView(breathCircleMiddle, FrameLayout.LayoutParams(midSz, midSz, Gravity.CENTER))

        // Inner circle — 150dp
        val innerSz = (150 * d).toInt()
        breathCircleInner = CircleView(this, accentColor).apply { alpha = 0.7f }
        area.addView(breathCircleInner, FrameLayout.LayoutParams(innerSz, innerSz, Gravity.CENTER))

        // Progress ring — 160dp
        val ringSz = (160 * d).toInt()
        progressView = CircularProgressView(this, accentColor, 3 * d)
        area.addView(progressView, FrameLayout.LayoutParams(ringSz, ringSz, Gravity.CENTER))

        // Timer text
        tvTimer = TextView(this).apply {
            text = "60"
            setTextColor(textPrimary)
            textSize = 44f
            typeface = android.graphics.Typeface.create("sans-serif-light", android.graphics.Typeface.NORMAL)
            gravity = Gravity.CENTER
        }
        area.addView(tvTimer, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))

        // Breath hint
        tvBreathHint = TextView(this).apply {
            text = "Вдох..."
            setTextColor(accentColor)
            textSize = 16f
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            gravity = Gravity.CENTER
            setPadding(0, (20 * d).toInt(), 0, 0)
        }
        content.addView(tvBreathHint, wrapCenter())

        // Flex spacer
        content.addView(View(this), LinearLayout.LayoutParams(0, 0, 0.6f))

        // ── Note input ──
        val accentCSL = android.content.res.ColorStateList.valueOf(accentColor)
        val hintCSL = android.content.res.ColorStateList.valueOf(textSecondary)

        tilNote = TextInputLayout(this, null,
            com.google.android.material.R.attr.textInputOutlinedStyle
        ).apply {
            hint = "Зачем ты хочешь это открыть?"
            boxBackgroundMode = TextInputLayout.BOX_BACKGROUND_OUTLINE
            setBoxCornerRadii(16 * d, 16 * d, 16 * d, 16 * d)
            isCounterEnabled = true
            counterMaxLength = 200
            boxBackgroundColor = Color.TRANSPARENT
            setBoxStrokeColorStateList(accentCSL)
            boxStrokeColor = accentColor
            defaultHintTextColor = hintCSL
            hintTextColor = accentCSL
            counterTextColor = hintCSL
        }
        etNote = TextInputEditText(tilNote.context).apply {
            maxLines = 2
            textSize = 14f
            setTextColor(textPrimary)
            setHintTextColor(textSecondary)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                textCursorDrawable?.setTint(accentColor)
            }
        }
        tilNote.addView(etNote)
        content.addView(tilNote, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = (24 * d).toInt()
            marginEnd = (24 * d).toInt()
        })

        // Spacer
        content.addView(View(this), lp(0, (16 * d).toInt()))

        // ── Button ──
        val btnTextColor = if (isDark) Color.parseColor("#0A0F0F") else Color.WHITE
        btnProceed = MaterialButton(this, null,
            com.google.android.material.R.attr.materialButtonStyle
        ).apply {
            text = "Подожди..."
            isEnabled = false
            alpha = 0.4f
            cornerRadius = (16 * d).toInt()
            textSize = 15f
            isAllCaps = false
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            setBackgroundColor(accentColor)
            setTextColor(btnTextColor)
            setPadding(0, (14 * d).toInt(), 0, (14 * d).toInt())
            setOnClickListener { onProceedClicked() }
        }
        content.addView(btnProceed, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (56 * d).toInt()
        ).apply {
            marginStart = (24 * d).toInt()
            marginEnd = (24 * d).toInt()
            bottomMargin = (36 * d).toInt()
        })

        setContentView(root)
    }

    private fun lp(w: Int, h: Int) = LinearLayout.LayoutParams(w, h)
    private fun wrapCenter() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    ).apply { gravity = Gravity.CENTER_HORIZONTAL }

    // ══════════════════════════════════════════════════════════
    //  TIMER & ACTIONS
    // ══════════════════════════════════════════════════════════

    private fun onProceedClicked() {
        if (didProceedToApp) return
        didProceedToApp = true
        Log.d(TAG, "User clicked Proceed for: $targetPackage")
        saveNoteOnce()

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.putString(AppMonitorService.KEY_PAUSE_CONFIRMED_PACKAGE, targetPackage)
        editor.putLong(AppMonitorService.KEY_PAUSE_CONFIRMED_AT, System.currentTimeMillis())

        if (prefs.getBoolean(KEY_COOLDOWN_ENABLED, true)) {
            editor.putLong(KEY_COOLDOWN_PREFIX + targetPackage, System.currentTimeMillis())
            Log.d(TAG, "Cooldown timestamp set for $targetPackage")
        }
        editor.commit()
        launchTargetApp()
        finish()
    }

    override fun onPause() {
        super.onPause()
        if (!didProceedToApp) {
            saveNoteOnce()
            Log.d(TAG, "onPause without proceed")
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

    private fun startTimer(durationMs: Long) {
        timer?.cancel()
        timer = object : CountDownTimer(durationMs, TICK_INTERVAL_MS) {
            override fun onTick(millisLeft: Long) {
                tvTimer.text = (millisLeft / 1000).toInt().toString()
                progressView.setProgress(millisLeft.toFloat() / durationMs)
            }
            override fun onFinish() {
                timerFinished = true
                tvTimer.text = "0"
                progressView.setProgress(0f)
                activateButton()
            }
        }.start()
    }

    private fun activateButton() {
        btnProceed.isEnabled = true
        btnProceed.text = "Открыть $appName"
        btnProceed.animate().alpha(1f).setDuration(500)
            .setInterpolator(OvershootInterpolator(1.2f)).start()
    }

    // ══════════════════════════════════════════════════════════
    //  BREATH ANIMATION
    // ══════════════════════════════════════════════════════════

    private fun startBreathAnimation() { runBreathCycle() }

    private fun runBreathCycle() {
        val i = AccelerateDecelerateInterpolator()

        // Outer
        val ioX = ObjectAnimator.ofFloat(breathCircleOuter, "scaleX", 1f, 1.3f).apply { duration = INHALE_MS; interpolator = i }
        val ioY = ObjectAnimator.ofFloat(breathCircleOuter, "scaleY", 1f, 1.3f).apply { duration = INHALE_MS; interpolator = i }
        val ioA = ObjectAnimator.ofFloat(breathCircleOuter, "alpha", 0.2f, 0.45f).apply { duration = INHALE_MS }
        val eoX = ObjectAnimator.ofFloat(breathCircleOuter, "scaleX", 1.3f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val eoY = ObjectAnimator.ofFloat(breathCircleOuter, "scaleY", 1.3f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val eoA = ObjectAnimator.ofFloat(breathCircleOuter, "alpha", 0.45f, 0.2f).apply { duration = EXHALE_MS }

        // Middle
        val imX = ObjectAnimator.ofFloat(breathCircleMiddle, "scaleX", 1f, 1.2f).apply { duration = INHALE_MS; interpolator = i }
        val imY = ObjectAnimator.ofFloat(breathCircleMiddle, "scaleY", 1f, 1.2f).apply { duration = INHALE_MS; interpolator = i }
        val imA = ObjectAnimator.ofFloat(breathCircleMiddle, "alpha", 0.35f, 0.6f).apply { duration = INHALE_MS }
        val emX = ObjectAnimator.ofFloat(breathCircleMiddle, "scaleX", 1.2f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val emY = ObjectAnimator.ofFloat(breathCircleMiddle, "scaleY", 1.2f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val emA = ObjectAnimator.ofFloat(breathCircleMiddle, "alpha", 0.6f, 0.35f).apply { duration = EXHALE_MS }

        // Inner
        val iiX = ObjectAnimator.ofFloat(breathCircleInner, "scaleX", 1f, 1.12f).apply { duration = INHALE_MS; interpolator = i }
        val iiY = ObjectAnimator.ofFloat(breathCircleInner, "scaleY", 1f, 1.12f).apply { duration = INHALE_MS; interpolator = i }
        val iiA = ObjectAnimator.ofFloat(breathCircleInner, "alpha", 0.7f, 0.9f).apply { duration = INHALE_MS }
        val eiX = ObjectAnimator.ofFloat(breathCircleInner, "scaleX", 1.12f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val eiY = ObjectAnimator.ofFloat(breathCircleInner, "scaleY", 1.12f, 1f).apply { duration = EXHALE_MS; interpolator = i }
        val eiA = ObjectAnimator.ofFloat(breathCircleInner, "alpha", 0.9f, 0.7f).apply { duration = EXHALE_MS }

        val hold = ValueAnimator.ofFloat(0f, 1f).apply { duration = HOLD_MS }

        ioX.addUpdateListener { if (it.animatedFraction < 0.05f) tvBreathHint.text = "Вдох..." }
        hold.addUpdateListener { if (it.animatedFraction < 0.05f) tvBreathHint.text = "Задержка..." }
        eoX.addUpdateListener { if (it.animatedFraction < 0.05f) tvBreathHint.text = "Выдох..." }

        val inhale = AnimatorSet().apply {
            playTogether(ioX, ioY, ioA, imX, imY, imA, iiX, iiY, iiA)
        }
        val exhale = AnimatorSet().apply {
            playTogether(eoX, eoY, eoA, emX, emY, emA, eiX, eiY, eiA)
        }

        breathAnimator = AnimatorSet().apply {
            playSequentially(inhale, hold, exhale)
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    if (!isFinishing && !isDestroyed) runBreathCycle()
                }
            })
            start()
        }
    }

    // ══════════════════════════════════════════════════════════
    //  NOTE & LAUNCH
    // ══════════════════════════════════════════════════════════

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

    private fun launchTargetApp() {
        if (targetPackage.isEmpty()) return
        try {
            val li = packageManager.getLaunchIntentForPackage(targetPackage)
            if (li != null) {
                li.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(li)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch $targetPackage", e)
        }
    }
}