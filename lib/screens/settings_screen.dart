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
  bool _loading = true;

  static const _privacyPolicyUrl = 'https://example.com/privacy';

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
      _batteryExempt = perms.battery;
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

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить все данные?'),
        content: const Text(
          'Будут удалены все заметки, список приложений и настройки. '
          'Это нельзя отменить.',
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
      await PlatformChannel.stopMonitorService();
      await NotesRepository.clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('monitored_packages');
      await PlatformChannel.setCooldownMinutes(5);
      await PlatformChannel.setCooldownEnabled(true);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              children: [
                // ── Сервис ──
                _sectionHeader(cs, 'Основное'),
                _buildCard(
                  cs,
                  isDark,
                  child: SwitchListTile(
                    title: const Text('Защита активна'),
                    subtitle: Text(
                      _serviceRunning ? 'Фоновый сервис работает' : 'Сервис остановлен',
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
                ),

                if (!_usageGranted || !_overlayGranted) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Не все разрешения выданы',
                              style: TextStyle(fontSize: 13, color: cs.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Приложения ──
                _sectionHeader(cs, 'Приложения'),
                _buildCard(
                  cs,
                  isDark,
                  child: ListTile(
                    leading: Icon(Icons.apps_rounded, color: cs.primary),
                    title: const Text('Контролируемые приложения'),
                    subtitle: Text('Выбрано: $_monitoredCount'),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                      );
                      _refresh();
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // ── Разрешения ──
                _sectionHeader(cs, 'Разрешения'),
                _buildCard(
                  cs,
                  isDark,
                  child: Column(
                    children: [
                      _permissionTile(
                        cs,
                        title: 'Доступ к использованию',
                        granted: _usageGranted,
                        onTap: () => PlatformChannel.requestUsageAccess(),
                      ),
                      Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                      _permissionTile(
                        cs,
                        title: 'Наложение поверх приложений',
                        granted: _overlayGranted,
                        onTap: () => PlatformChannel.requestOverlayPermission(),
                      ),
                      Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                      _permissionTile(
                        cs,
                        title: 'Оптимизация батареи',
                        granted: _batteryExempt,
                        onTap: () => PlatformChannel.requestBatteryOptimizationExemption(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Обновить статус'),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Данные ──
                _sectionHeader(cs, 'Данные и конфиденциальность'),
                _buildCard(
                  cs,
                  isDark,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.delete_forever_rounded, color: cs.error),
                        title: const Text('Удалить все данные'),
                        subtitle: const Text('Заметки, настройки, список'),
                        onTap: _deleteAllData,
                      ),
                      Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                      ListTile(
                        leading: Icon(Icons.privacy_tip_outlined, color: cs.onSurfaceVariant),
                        title: const Text('Политика конфиденциальности'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: _openPrivacyPolicy,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── О приложении ──
                _sectionHeader(cs, 'О приложении'),
                _buildCard(
                  cs,
                  isDark,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
                        title: const Text('Mindful Pause'),
                        subtitle: const Text('Версия 1.0.0'),
                      ),
                      Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.3)),
                      ListTile(
                        leading: Icon(Icons.replay_rounded, color: cs.onSurfaceVariant),
                        title: const Text('Показать онбординг'),
                        onTap: () => _resetOnboarding(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionHeader(ColorScheme cs, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.primary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildCard(ColorScheme cs, bool isDark, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
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
        size: 22,
      ),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        granted ? 'Выдано' : 'Не выдано',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
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
        content: const Text('Вы увидите приветственный экран.'),
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