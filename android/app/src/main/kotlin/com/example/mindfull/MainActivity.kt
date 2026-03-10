package com.example.mindfull

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var permissionHelper: PermissionHelper

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
                "requestUsageAccess" -> {
                    permissionHelper.requestUsageStatsPermission()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    permissionHelper.requestOverlayPermission()
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
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, AppMonitorService::class.java)
                    intent.action = AppMonitorService.ACTION_STOP
                    startService(intent)
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
                else -> result.notImplemented()
            }
        }
    }
}