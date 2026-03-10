import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/services/notes_repository.dart';
import 'package:mindfull/screens/app_selection_screen.dart';
import 'package:mindfull/screens/onboarding_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _usageGranted = false;
  bool _overlayGranted = false;
  bool _batteryExempt = false;
  int _monitoredCount = 0;
  int _cooldownMinutes = 5;
  bool _loading = true;

  static const _cooldownOptions = [1, 5, 15, 30, 60];
  static const _privacyPolicyUrl = 'https://example.com/privacy'; // TODO: заменить на реальный URL

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final running = await PlatformChannel.isServiceRunning();
    final perms = await PlatformChannel.checkAllPermissions();
    final prefs = await SharedPreferences.getInstance();
    final monitored = prefs.getStringList('monitored_packages') ?? [];
    final cooldown = prefs.getInt('cooldown_minutes') ?? 5;
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _usageGranted = perms.usageAccess;
      _overlayGranted = perms.overlay;
      _batteryExempt = perms.battery;
      _monitoredCount = monitored.length;
      _cooldownMinutes = cooldown;
      _loading = false;
    });
  }

  Future<void> _toggleService(bool enable) async {
    try {
      if (enable) {
        final prefs = await SharedPreferences.getInstance();
        final monitored = prefs.getStringList('monitored_packages') ?? [];
        await PlatformChannel.updateMonitoredApps(monitored);
        await PlatformChannel.startMonitorService();
      } else {
        await PlatformChannel.stopMonitorService();
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _setCooldown(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cooldown_minutes', minutes);
    setState(() => _cooldownMinutes = minutes);
  }

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить все данные?'),
        content: const Text(
          'Будут удалены:\n'
          '• Все заметки\n'
          '• Список контролируемых приложений\n'
          '• Все настройки\n\n'
          'Это действие нельзя отменить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Останавливаем сервис
      await PlatformChannel.stopMonitorService();

      // Очищаем заметки
      await NotesRepository.clearAll();

      // Очищаем SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('monitored_packages');
      await prefs.remove('cooldown_minutes');
      await prefs.setBool('service_enabled', false);
      // Не сбрасываем onboarding_done чтобы не показывать онбординг заново

      // Обновляем мониторинг (пустой список)
      await PlatformChannel.updateMonitoredApps([]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все данные удалены')),
      );
      _refresh();
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Основной toggle ──
                _section(cs, 'Основное'),
                SwitchListTile(
                  title: const Text('Защита активна'),
                  subtitle: Text(
                    _serviceRunning
                        ? 'Фоновый сервис работает'
                        : 'Сервис остановлен',
                  ),
                  secondary: Icon(
                    _serviceRunning ? Icons.shield_rounded : Icons.shield_outlined,
                    color: _serviceRunning ? cs.primary : cs.onSurfaceVariant,
                  ),
                  value: _serviceRunning,
                  onChanged: (_monitoredCount > 0 && _usageGranted && _overlayGranted)
                      ? (val) => _toggleService(val)
                      : null,
                ),

                if (!_usageGranted || !_overlayGranted)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Не все разрешения выданы. Сервис не может работать.',
                                style: TextStyle(fontSize: 13, color: cs.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const Divider(height: 32),

                // ── Приложения ──
                _section(cs, 'Приложения'),
                ListTile(
                  leading: Icon(Icons.apps_rounded, color: cs.primary),
                  title: const Text('Контролируемые приложения'),
                  subtitle: Text('Выбрано: $_monitoredCount'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                    );
                    _refresh();
                  },
                ),

                const Divider(height: 32),

                // ── Пауза ──
                _section(cs, 'Пауза'),
                ListTile(
                  leading: Icon(Icons.timer_rounded, color: cs.primary),
                  title: const Text('Cooldown между паузами'),
                  subtitle: Text(_cooldownLabel(_cooldownMinutes)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showCooldownPicker(cs),
                ),

                const Divider(height: 32),

                // ── Разрешения ──
                _section(cs, 'Разрешения'),
                _permissionTile(
                  cs,
                  title: 'Доступ к использованию',
                  granted: _usageGranted,
                  onTap: () async {
                    await PlatformChannel.requestUsageAccess();
                  },
                ),
                _permissionTile(
                  cs,
                  title: 'Наложение поверх приложений',
                  granted: _overlayGranted,
                  onTap: () async {
                    await PlatformChannel.requestOverlayPermission();
                  },
                ),
                _permissionTile(
                  cs,
                  title: 'Оптимизация батареи отключена',
                  granted: _batteryExempt,
                  onTap: () async {
                    await PlatformChannel.requestBatteryOptimizationExemption();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Обновить статус разрешений'),
                  ),
                ),

                const Divider(height: 32),

                // ── Данные ──
                _section(cs, 'Данные'),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded, color: cs.error),
                  title: const Text('Удалить все данные'),
                  subtitle: const Text('Заметки, настройки, список приложений'),
                  onTap: _deleteAllData,
                ),

                const Divider(height: 32),

                // ── О приложении ──
                _section(cs, 'О приложении'),
                ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                  title: const Text('Mindful Pause'),
                  subtitle: const Text('Версия 1.0.0'),
                ),
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: cs.onSurfaceVariant),
                  title: const Text('Политика конфиденциальности'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: _openPrivacyPolicy,
                ),
                ListTile(
                  leading: Icon(Icons.replay_rounded, color: cs.onSurfaceVariant),
                  title: const Text('Показать онбординг'),
                  subtitle: const Text('Запустить приветственный экран заново'),
                  onTap: () => _resetOnboarding(context),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  void _showCooldownPicker(ColorScheme cs) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Повторная пауза не сработает в течение выбранного времени '
                'после последней паузы для того же приложения.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
            ..._cooldownOptions.map((minutes) => RadioListTile<int>(
              title: Text(_cooldownLabel(minutes)),
              value: minutes,
              groupValue: _cooldownMinutes,
              onChanged: (v) {
                if (v != null) {
                  _setCooldown(v);
                  Navigator.of(ctx).pop();
                }
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _cooldownLabel(int minutes) {
    if (minutes == 1) return '1 минута';
    if (minutes < 5) return '$minutes минуты';
    if (minutes == 60) return '1 час';
    return '$minutes минут';
  }

  Widget _section(ColorScheme cs, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
    );
  }

  Widget _permissionTile(
    ColorScheme cs, {
    required String title,
    required bool granted,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        granted ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: granted ? cs.primary : cs.error,
      ),
      title: Text(title),
      subtitle: Text(granted ? 'Выдано' : 'Не выдано'),
      trailing: granted
          ? null
          : TextButton(
              onPressed: onTap,
              child: const Text('Выдать'),
            ),
    );
  }

  Future<void> _resetOnboarding(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить онбординг?'),
        content: const Text('Вы увидите приветственный экран при следующем запуске.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done', false);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    }
  }
}