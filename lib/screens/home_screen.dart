import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mindfull/services/platform_channel.dart';
import 'package:mindfull/screens/app_selection_screen.dart';
import 'package:mindfull/screens/settings_screen.dart';
import 'package:mindfull/screens/notes_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _loading = true;
  int _monitoredCount = 0;
  bool _permissionsOk = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _init() async {
    await _refresh();
    if (!_serviceRunning && _monitoredCount > 0 && _permissionsOk) {
      await _startService();
    }
  }

  Future<void> _refresh() async {
    final running = await PlatformChannel.isServiceRunning();
    final perms = await PlatformChannel.checkAllPermissions();
    final prefs = await SharedPreferences.getInstance();
    final monitored = prefs.getStringList('monitored_packages') ?? [];
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _monitoredCount = monitored.length;
      _permissionsOk = perms.usageAccess && perms.overlay;
      _loading = false;
    });
  }

  Future<void> _startService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final monitored = prefs.getStringList('monitored_packages') ?? [];
      await PlatformChannel.updateMonitoredApps(monitored);
      await PlatformChannel.startMonitorService();
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _stopService() async {
    try {
      await PlatformChannel.stopMonitorService();
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _openAppSelection() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mindful Pause'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              _refresh();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // ── Статус сервиса ──
                  _buildStatusCard(cs),
                  const SizedBox(height: 20),

                  // ── Контролируемые приложения ──
                  _buildActionTile(
                    cs,
                    icon: Icons.apps_rounded,
                    title: 'Контролируемые приложения',
                    subtitle: _monitoredCount > 0
                        ? 'Выбрано: $_monitoredCount'
                        : 'Нажмите, чтобы выбрать',
                    onTap: _openAppSelection,
                  ),
                  const SizedBox(height: 12),

                  // ── История заметок ──
                  _buildActionTile(
                    cs,
                    icon: Icons.note_alt_outlined,
                    title: 'История заметок',
                    subtitle: 'Что вы писали на экранах паузы',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotesHistoryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _serviceRunning
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            _serviceRunning ? Icons.shield_rounded : Icons.shield_outlined,
            size: 56,
            color: _serviceRunning ? cs.primary : cs.error,
          ),
          const SizedBox(height: 16),
          Text(
            _serviceRunning ? 'Защита активна' : 'Защита отключена',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _serviceRunning
                ? 'Отслеживается приложений: $_monitoredCount'
                : _monitoredCount > 0
                    ? 'Выбрано приложений: $_monitoredCount'
                    : 'Сначала выберите приложения для контроля',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
          if (!_permissionsOk) ...[
            const SizedBox(height: 12),
            Text(
              'Не все разрешения выданы — откройте настройки',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.error),
            ),
          ],
          const SizedBox(height: 24),
          if (_monitoredCount > 0 && _permissionsOk)
            FilledButton.icon(
              onPressed: _serviceRunning ? _stopService : _startService,
              icon: Icon(
                _serviceRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(_serviceRunning ? 'Остановить' : 'Запустить'),
            ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: cs.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}