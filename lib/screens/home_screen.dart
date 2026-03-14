import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _serviceRunning = false;
  bool _loading = true;
  int _monitoredCount = 0;
  bool _permissionsOk = false;
  int _cooldownMinutes = 5;
  bool _cooldownEnabled = true;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _cooldownOptions = [1, 3, 5, 10, 15, 30, 60];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
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
    final cooldown = await PlatformChannel.getCooldownMinutes();
    final cooldownEnabled = await PlatformChannel.isCooldownEnabled();
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _monitoredCount = monitored.length;
      _permissionsOk = perms.usageAccess && perms.overlay;
      _cooldownMinutes = cooldown;
      _cooldownEnabled = cooldownEnabled;
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
      _showSnackBar('Ошибка: $e');
    }
  }

  Future<void> _stopService() async {
    try {
      await PlatformChannel.stopMonitorService();
      await Future.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Ошибка: $e');
    }
  }

  Future<void> _toggleService() async {
    HapticFeedback.mediumImpact();
    if (_serviceRunning) {
      await _stopService();
    } else {
      await _startService();
    }
  }

  Future<void> _setCooldown(int minutes) async {
    await PlatformChannel.setCooldownMinutes(minutes);
    setState(() => _cooldownMinutes = minutes);
  }

  Future<void> _toggleCooldownEnabled(bool enabled) async {
    HapticFeedback.lightImpact();
    await PlatformChannel.setCooldownEnabled(enabled);
    setState(() => _cooldownEnabled = enabled);
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _cooldownLabel(int minutes) {
    if (minutes < 60) return '$minutes мин';
    return '1 час';
  }

  String _cooldownLabelFull(int minutes) {
    if (minutes == 1) return '1 минута';
    if (minutes < 5) return '$minutes минуты';
    if (minutes == 60) return '1 час';
    return '$minutes минут';
  }

  /// Текст-подсказка для кнопки когда она неактивна
  String? get _disabledReason {
    if (_monitoredCount == 0) return 'Сначала выберите приложения для контроля';
    if (!_permissionsOk) return 'Выдайте необходимые разрешения в настройках';
    return null;
  }

  bool get _canToggle => _monitoredCount > 0 && _permissionsOk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      'Mindful Pause',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(Icons.settings_rounded, color: cs.onSurfaceVariant),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                          _refresh();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 8),
                        _buildHeroCard(cs, isDark),
                        const SizedBox(height: 20),
                        _buildCooldownCard(cs, isDark),
                        const SizedBox(height: 16),
                        _buildQuickAction(
                          cs, isDark,
                          icon: Icons.apps_rounded,
                          title: 'Приложения',
                          value: _monitoredCount > 0
                              ? '$_monitoredCount выбрано'
                              : 'Нажмите, чтобы выбрать',
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AppSelectionScreen()),
                            );
                            _refresh();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildQuickAction(
                          cs, isDark,
                          icon: Icons.history_rounded,
                          title: 'История заметок',
                          value: 'Что вы писали на экранах паузы',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const NotesHistoryScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                      ]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  HERO STATUS CARD
  // ══════════════════════════════════════════════════════════

  Widget _buildHeroCard(ColorScheme cs, bool isDark) {
    final active = _serviceRunning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: isDark ? 0.15 : 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: active
              ? cs.primary.withValues(alpha: 0.2)
              : cs.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Animated shield
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: active ? _pulseAnimation.value : 1.0,
                child: child,
              );
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? cs.primary.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
              ),
              child: Icon(
                active ? Icons.shield_rounded : Icons.shield_outlined,
                size: 36,
                color: active ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            active ? 'Защита активна' : 'Защита отключена',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            active
                ? 'Отслеживается: $_monitoredCount'
                : _monitoredCount > 0
                    ? 'Готово к запуску · $_monitoredCount приложений'
                    : 'Сначала выберите приложения',
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),

          // Предупреждения
          if (!_permissionsOk && !active) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Нужны разрешения — откройте настройки',
                      style: TextStyle(fontSize: 12, color: cs.error, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Кнопка ВСЕГДА видна ──
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _canToggle ? _toggleService : null,
              style: FilledButton.styleFrom(
                backgroundColor: active
                    ? cs.error.withValues(alpha: 0.9)
                    : cs.primary,
                foregroundColor: active ? cs.onError : cs.onPrimary,
                disabledBackgroundColor: cs.surfaceContainerHighest,
                disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active
                        ? Icons.stop_rounded
                        : _canToggle
                            ? Icons.play_arrow_rounded
                            : Icons.lock_outline_rounded,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active
                        ? 'Остановить защиту'
                        : _canToggle
                            ? 'Включить защиту'
                            : 'Включить защиту',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),

          // Подсказка почему кнопка неактивна
          if (!_canToggle && !active) ...[
            const SizedBox(height: 10),
            Text(
              _disabledReason ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  COOLDOWN CARD
  // ══════════════════════════════════════════════════════════

  Widget _buildCooldownCard(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.timer_rounded, size: 22, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cooldown',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      _cooldownEnabled
                          ? 'Перерыв ${_cooldownLabelFull(_cooldownMinutes)} после подтверждения'
                          : 'Пауза при каждом входе',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch.adaptive(
                  value: _cooldownEnabled,
                  onChanged: _toggleCooldownEnabled,
                ),
              ),
            ],
          ),
          if (_cooldownEnabled) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _cooldownOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final minutes = _cooldownOptions[index];
                  final selected = _cooldownMinutes == minutes;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _setCooldown(minutes);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary
                            : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? null
                            : Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.3),
                                width: 1,
                              ),
                      ),
                      child: Text(
                        _cooldownLabel(minutes),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  QUICK ACTION
  // ══════════════════════════════════════════════════════════

  Widget _buildQuickAction(
    ColorScheme cs, bool isDark, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}