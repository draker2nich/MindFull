import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Информация об установленном приложении
class AppInfo {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? icon;
    final b64 = map['iconBase64'] as String?;
    if (b64 != null && b64.isNotEmpty) {
      icon = base64Decode(b64);
    }
    return AppInfo(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
      iconBytes: icon,
    );
  }
}

/// Обёртка над MethodChannel для общения с нативным Android кодом.
class PlatformChannel {
  PlatformChannel._();

  static const _channel = MethodChannel('com.example.mindfull/permissions');
  static const _serviceChannel = MethodChannel('com.example.mindfull/service');
  static const _appsChannel = MethodChannel('com.example.mindfull/apps');

  // ── Разрешения ──

  static Future<bool> hasUsageAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> hasBatteryOptimizationExemption() async {
    try {
      return await _channel.invokeMethod<bool>('hasBatteryOptimizationExemption') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> requestUsageAccess() async {
    await _channel.invokeMethod('requestUsageAccess');
  }

  static Future<void> requestOverlayPermission() async {
    await _channel.invokeMethod('requestOverlayPermission');
  }

  static Future<void> requestBatteryOptimizationExemption() async {
    await _channel.invokeMethod('requestBatteryOptimizationExemption');
  }

  static Future<({bool usageAccess, bool overlay, bool battery})> checkAllPermissions() async {
    final usage = await hasUsageAccess();
    final overlay = await hasOverlayPermission();
    final battery = await hasBatteryOptimizationExemption();
    return (usageAccess: usage, overlay: overlay, battery: battery);
  }

  // ── Foreground Service ──

  static Future<void> startMonitorService() async {
    await _serviceChannel.invokeMethod('startService');
  }

  static Future<void> stopMonitorService() async {
    await _serviceChannel.invokeMethod('stopService');
  }

  static Future<bool> isServiceRunning() async {
    try {
      return await _serviceChannel.invokeMethod<bool>('isServiceRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> updateMonitoredApps(List<String> packageNames) async {
    await _serviceChannel.invokeMethod('updateMonitoredApps', {
      'packages': packageNames,
    });
  }

  static Future<void> setCooldownMinutes(int minutes) async {
    await _serviceChannel.invokeMethod('setCooldownMinutes', {
      'minutes': minutes,
    });
  }

  static Future<int> getCooldownMinutes() async {
    try {
      return await _serviceChannel.invokeMethod<int>('getCooldownMinutes') ?? 5;
    } on PlatformException {
      return 5;
    }
  }

  // ── Установленные приложения ──

  static Future<List<AppInfo>> getInstalledApps() async {
    try {
      final result = await _appsChannel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (result == null) return [];
      return result
          .cast<Map<dynamic, dynamic>>()
          .map(AppInfo.fromMap)
          .toList();
    } on PlatformException {
      return [];
    }
  }
}