import 'package:flutter/material.dart';
import '../services/platform_channel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  bool _loading = true;

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
    // Обновляем статус сервиса при возврате в приложение
    if (state == AppLifecycleState.resumed) {
      _checkService();
    }
  }

  Future<void> _init() async {
    await _checkService();
    // Автозапуск сервиса при первом входе
    if (!_serviceRunning) {
      await _startService();
    }
  }

  Future<void> _checkService() async {
    final running = await PlatformChannel.isServiceRunning();
    if (!mounted) return;
    setState(() {
      _serviceRunning = running;
      _loading = false;
    });
  }

  Future<void> _startService() async {
    try {
      await PlatformChannel.startMonitorService();
      await _checkService();
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
      await _checkService();
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
      appBar: AppBar(
        title: const Text('Mindful Pause'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Статус сервиса
                  Container(
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
                          _serviceRunning
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
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
                              ? 'Приложение отслеживает запуск контролируемых приложений'
                              : 'Включите, чтобы начать отслеживание',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _serviceRunning ? _stopService : _startService,
                          icon: Icon(_serviceRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                          label: Text(_serviceRunning ? 'Остановить' : 'Запустить'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Заглушка для будущих экранов
                  Text(
                    'Выбор приложений и настройки — в Этапе 3',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}