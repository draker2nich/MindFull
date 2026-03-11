package com.example.mindfull

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private lateinit var permissionHelper: PermissionHelper

    companion object {
        private const val PREFS_NAME = "mindful_prefs"
        private const val KEY_SERVICE_ENABLED = "service_enabled"
        private const val NOTIFICATION_PERMISSION_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        permissionHelper = PermissionHelper(this)

        // ── Канал разрешений ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.mindfull/permissions"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> {
                    result.success(permissionHelper.hasUsageStatsPermission())
                }
                "hasOverlayPermission" -> {
                    result.success(permissionHelper.hasOverlayPermission())
                }
                "hasBatteryOptimizationExemption" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestUsageAccess" -> {
                    permissionHelper.requestUsageStatsPermission()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    permissionHelper.requestOverlayPermission()
                    result.success(null)
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Канал сервиса ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.mindfull/service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    intent.action = AppMonitorService.ACTION_START
                    startForegroundService(intent)
                    // Запоминаем что пользователь включил сервис (для BootReceiver)
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_SERVICE_ENABLED, true)
                        .apply()
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    intent.action = AppMonitorService.ACTION_STOP
                    startService(intent)
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_SERVICE_ENABLED, false)
                        .apply()
                    result.success(null)
                }
                "isServiceRunning" -> {
                    result.success(AppMonitorService.isRunning)
                }
                "updateMonitoredApps" -> {
                    val packages = call.argument<List<String>>("packages")
                    if (packages != null) {
                        AppMonitorService.updateMonitoredPackages(this, packages)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "packages is null", null)
                    }
                }
                "setCooldownMinutes" -> {
                    val minutes = call.argument<Int>("minutes")
                    if (minutes != null) {
                        getSharedPreferences("mindful_prefs", Context.MODE_PRIVATE)
                            .edit()
                            .putInt("cooldown_minutes", minutes)
                            .apply()
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "minutes is null", null)
                    }
                }
                "getCooldownMinutes" -> {
                    val minutes = getSharedPreferences("mindful_prefs", Context.MODE_PRIVATE)
                        .getInt("cooldown_minutes", 5)
                    result.success(minutes)
                }
                else -> result.notImplemented()
            }
        }

        // ── Канал приложений ──
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.mindfull/apps"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    Thread {
                        val apps = getInstalledLauncherApps()
                        runOnUiThread { result.success(apps) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Battery Optimization ──

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption() {
        if (!isBatteryOptimizationIgnored()) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    // ── Установленные приложения ──

    private fun getInstalledLauncherApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = packageManager.queryIntentActivities(intent, 0)
        val myPackage = packageName

        return resolveInfos
            .filter { it.activityInfo.packageName != myPackage }
            .sortedBy { it.loadLabel(packageManager).toString().lowercase() }
            .map { ri ->
                val pkg = ri.activityInfo.packageName
                val label = ri.loadLabel(packageManager).toString()
                val icon = ri.loadIcon(packageManager)
                mapOf(
                    "packageName" to pkg,
                    "appName" to label,
                    "iconBase64" to drawableToBase64(icon)
                )
            }
    }

    private fun drawableToBase64(drawable: Drawable): String {
        val size = 72
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
        bitmap.recycle()
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}