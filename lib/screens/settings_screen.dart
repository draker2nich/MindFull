import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/screens/app_selection_screen.dart';
import 'package:mindfull/screens/onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _usageGranted = false;
  bool _overlayGranted = false;
  int _monitoredCount = 0;
  bool _loading = true;

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
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _usageGranted = perms.usageAccess;
      _overlayGranted = perms.overlay;
      _monitoredCount = monitored.length;
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

                if (!_usageGranted || !_overlayGranted) ...[
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
                ],

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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Обновить статус разрешений'),
                  ),
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
        MaterialPageRoute(builder: (_) => OnboardingScreen()),
        (_) => false,
      );
    }
  }
}