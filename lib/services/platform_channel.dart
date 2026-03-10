import 'package:flutter/services.dart';

/// Обёртка над MethodChannel для общения с нативным Android кодом.
class PlatformChannel {
  PlatformChannel._();

  static const _channel = MethodChannel('com.example.mindfull/permissions');
  static const _serviceChannel = MethodChannel('com.example.mindfull/service');

  // ── Разрешения ──

  /// Проверяет, выдано ли разрешение Usage Access (PACKAGE_USAGE_STATS)
  static Future<bool> hasUsageAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Проверяет, выдано ли разрешение Overlay (SYSTEM_ALERT_WINDOW)
  static Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Открывает системные настройки Usage Access
  static Future<void> requestUsageAccess() async {
    try {
      await _channel.invokeMethod('requestUsageAccess');
    } on PlatformException catch (e) {
      throw Exception('Не удалось открыть настройки: ${e.message}');
    }
  }

  /// Открывает системные настройки Overlay
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      throw Exception('Не удалось открыть настройки: ${e.message}');
    }
  }

  /// Проверяет оба разрешения разом
  static Future<({bool usageAccess, bool overlay})> checkAllPermissions() async {
    final usage = await hasUsageAccess();
    final overlay = await hasOverlayPermission();
    return (usageAccess: usage, overlay: overlay);
  }

  // ── Foreground Service ──

  /// Запускает фоновый сервис мониторинга
  static Future<void> startMonitorService() async {
    try {
      await _serviceChannel.invokeMethod('startService');
    } on PlatformException catch (e) {
      throw Exception('Не удалось запустить сервис: ${e.message}');
    }
  }

  /// Останавливает фоновый сервис
  static Future<void> stopMonitorService() async {
    try {
      await _serviceChannel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      throw Exception('Не удалось остановить сервис: ${e.message}');
    }
  }

  /// Проверяет, запущен ли сервис
  static Future<bool> isServiceRunning() async {
    try {
      return await _serviceChannel.invokeMethod<bool>('isServiceRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Передаёт список пакетов для отслеживания в сервис
  static Future<void> updateMonitoredApps(List<String> packageNames) async {
    try {
      await _serviceChannel.invokeMethod('updateMonitoredApps', {
        'packages': packageNames,
      });
    } on PlatformException catch (e) {
      throw Exception('Не удалось обновить список: ${e.message}');
    }
  }
}