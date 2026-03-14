import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'appTitle': 'Mindful Pause',

      // Home
      'protectionActive': 'Protection active',
      'protectionOff': 'Protection off',
      'monitored': 'Monitored: {count}',
      'readyToStart': 'Ready to start · {count} apps',
      'selectAppsFirst': 'Select apps first',
      'stopProtection': 'Stop protection',
      'enableProtection': 'Enable protection',
      'needPermissions': 'Permissions needed — open settings',
      'selectAppsHint': 'Select apps to monitor first',
      'grantPermissionsHint': 'Grant required permissions in settings',

      // Cooldown
      'cooldown': 'Cooldown',
      'cooldownDesc': '{minutes} break after confirmation',
      'cooldownEveryTime': 'Pause on every launch',
      'min': '{n} min',
      'hour1': '1 hour',
      'minute1': '1 minute',
      'minutesFew': '{n} minutes',
      'minutesMany': '{n} minutes',

      // Apps
      'apps': 'Apps',
      'appsSelected': '{count} selected',
      'tapToSelect': 'Tap to select',
      'notesHistory': 'Notes history',
      'notesHistoryDesc': 'What you wrote on pause screens',

      // App Selection
      'appSelection': 'App selection',
      'search': 'Search...',
      'tracked': 'Tracked',
      'allApps': 'All apps',
      'noApps': 'No apps',
      'nothingFound': 'Nothing found',
      'selected': 'Selected: {count}',
      'saveNoApps': 'Save without apps',
      'saveCount': 'Save ({count})',
      'loadError': 'Failed to load app list',
      'retry': 'Retry',

      // Notes
      'notesTitle': 'Notes history',
      'notesWithCount': 'Notes ({count})',
      'noNotesYet': 'No notes yet',
      'noNotesDesc':
          'They\'ll appear after you write something on the pause screen',
      'deleteNote': 'Delete note?',
      'deleteAllNotes': 'Delete all notes?',
      'cannotUndo': 'This cannot be undone.',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'clearAll': 'Clear all',

      // Settings
      'settings': 'Settings',
      'general': 'General',
      'protectionActiveDesc': 'Background service is running',
      'serviceStopped': 'Service stopped',
      'permissionsNotGranted': 'Not all permissions granted',
      'controlledApps': 'Controlled apps',
      'permissions': 'Permissions',
      'usageAccess': 'Usage access',
      'usageAccessDesc': 'Allows detecting which app is open',
      'overlayPermission': 'Display over other apps',
      'overlayPermissionDesc': 'Allows showing pause screen',
      'batteryOptimization': 'Battery optimization',
      'granted': 'Granted',
      'notGranted': 'Not granted',
      'grant': 'Grant',
      'refreshStatus': 'Refresh status',
      'dataAndPrivacy': 'Data & privacy',
      'deleteAllData': 'Delete all data',
      'deleteAllDataDesc': 'Notes, settings, list',
      'deleteAllDataConfirm': 'Delete all data?',
      'deleteAllDataWarning':
          'All notes, app list, and settings will be deleted. This cannot be undone.',
      'deleteEverything': 'Delete everything',
      'allDataDeleted': 'All data deleted',
      'privacyPolicy': 'Privacy policy',
      'about': 'About',
      'version': 'Version {v}',
      'showOnboarding': 'Show onboarding',
      'resetOnboarding': 'Reset onboarding?',
      'resetOnboardingDesc': 'You\'ll see the welcome screen.',
      'reset': 'Reset',
      'error': 'Error: {e}',

      // Language
      'language': 'Language',
      'langSystem': 'System',
      'langRu': 'Русский',
      'langEn': 'English',

      // Onboarding
      'onboardingTitle': 'Mindful Pause',
      'onboardingDesc':
          'A mindful pause before distracting apps.\nDoesn\'t block — gently brings attention back.',
      'next': 'Next',
      'selectApps': 'Select apps',
      'selectAppsDesc': 'Choose which apps to show a pause before',
      'pauseDuration': '60-second pause',
      'pauseDurationDesc': 'Breathing animation and time to think',
      'continueUsing': 'Continue',
      'continueUsingDesc': 'After the pause — free access to the app',
      'setupPermissions': 'Set up permissions',
      'twoPermissions': 'Two permissions needed',
      'twoPermissionsDesc':
          'Without them the app can\'t track other app launches',
      'checkPermissions': 'Check permissions',
      'grantBoth': 'Grant both permissions to continue',
      'batteryTitle': 'Battery optimization',
      'batteryDesc':
          'To keep protection stable, disable battery optimization for Mindful Pause. Otherwise the system may stop the background service.',
      'disableBatteryOpt': 'Disable battery optimization',
      'disableBatteryOptDesc': 'Tap and select "Allow"',
      'check': 'Check',
      'batteryDisabled':
          'Battery optimization disabled — service will work reliably',
      'start': 'Start',
      'skipWarning': 'You can skip, but the service may be unstable',

      // Pause Activity (Kotlin strings)
      'pauseTitle': 'Take a pause',
      'beforeOpening': 'before opening {app}',
      'inhale': 'Inhale...',
      'hold': 'Hold...',
      'exhale': 'Exhale...',
      'wait': 'Wait...',
      'openApp': 'Open {app}',
      'noteHint': 'Why do you want to open this?',

      // Notification
      'notifTitle': 'Mindful Pause',
      'notifText': 'Protection active · Apps: {count}',
      'notifChannelName': 'App monitoring',
      'notifChannelDesc': 'Mindful Pause tracks app launches',
      'notifStop': 'Turn off',
    },
    'ru': {
      'appTitle': 'Mindful Pause',

      'protectionActive': 'Защита активна',
      'protectionOff': 'Защита отключена',
      'monitored': 'Отслеживается: {count}',
      'readyToStart': 'Готово к запуску · {count} приложений',
      'selectAppsFirst': 'Сначала выберите приложения',
      'stopProtection': 'Остановить защиту',
      'enableProtection': 'Включить защиту',
      'needPermissions': 'Нужны разрешения — откройте настройки',
      'selectAppsHint': 'Сначала выберите приложения для контроля',
      'grantPermissionsHint': 'Выдайте необходимые разрешения в настройках',

      'cooldown': 'Cooldown',
      'cooldownDesc': 'Перерыв {minutes} после подтверждения',
      'cooldownEveryTime': 'Пауза при каждом входе',
      'min': '{n} мин',
      'hour1': '1 час',
      'minute1': '1 минута',
      'minutesFew': '{n} минуты',
      'minutesMany': '{n} минут',

      'apps': 'Приложения',
      'appsSelected': '{count} выбрано',
      'tapToSelect': 'Нажмите, чтобы выбрать',
      'notesHistory': 'История заметок',
      'notesHistoryDesc': 'Что вы писали на экранах паузы',

      'appSelection': 'Выбор приложений',
      'search': 'Поиск...',
      'tracked': 'Отслеживаемые',
      'allApps': 'Все приложения',
      'noApps': 'Нет приложений',
      'nothingFound': 'Ничего не найдено',
      'selected': 'Выбрано: {count}',
      'saveNoApps': 'Сохранить без приложений',
      'saveCount': 'Сохранить ({count})',
      'loadError': 'Не удалось загрузить список приложений',
      'retry': 'Повторить',

      'notesTitle': 'История заметок',
      'notesWithCount': 'Заметки ({count})',
      'noNotesYet': 'Заметок пока нет',
      'noNotesDesc':
          'Они появятся после того, как вы напишете что-нибудь на экране паузы',
      'deleteNote': 'Удалить заметку?',
      'deleteAllNotes': 'Удалить все заметки?',
      'cannotUndo': 'Это действие нельзя отменить.',
      'cancel': 'Отмена',
      'delete': 'Удалить',
      'clearAll': 'Очистить всё',

      'settings': 'Настройки',
      'general': 'Основное',
      'protectionActiveDesc': 'Фоновый сервис работает',
      'serviceStopped': 'Сервис остановлен',
      'permissionsNotGranted': 'Не все разрешения выданы',
      'controlledApps': 'Контролируемые приложения',
      'permissions': 'Разрешения',
      'usageAccess': 'Доступ к использованию',
      'usageAccessDesc': 'Позволяет определить, какое приложение открыто',
      'overlayPermission': 'Наложение поверх приложений',
      'overlayPermissionDesc': 'Позволяет показать экран паузы',
      'batteryOptimization': 'Оптимизация батареи',
      'granted': 'Выдано',
      'notGranted': 'Не выдано',
      'grant': 'Выдать',
      'refreshStatus': 'Обновить статус',
      'dataAndPrivacy': 'Данные и конфиденциальность',
      'deleteAllData': 'Удалить все данные',
      'deleteAllDataDesc': 'Заметки, настройки, список',
      'deleteAllDataConfirm': 'Удалить все данные?',
      'deleteAllDataWarning':
          'Будут удалены все заметки, список приложений и настройки. Это нельзя отменить.',
      'deleteEverything': 'Удалить всё',
      'allDataDeleted': 'Все данные удалены',
      'privacyPolicy': 'Политика конфиденциальности',
      'about': 'О приложении',
      'version': 'Версия {v}',
      'showOnboarding': 'Показать онбординг',
      'resetOnboarding': 'Сбросить онбординг?',
      'resetOnboardingDesc': 'Вы увидите приветственный экран.',
      'reset': 'Сбросить',
      'error': 'Ошибка: {e}',

      'language': 'Язык',
      'langSystem': 'Системный',
      'langRu': 'Русский',
      'langEn': 'English',

      'onboardingTitle': 'Mindful Pause',
      'onboardingDesc':
          'Осознанная пауза перед отвлекающими приложениями.\nНе блокирует — мягко возвращает внимание.',
      'next': 'Далее',
      'selectApps': 'Выберите приложения',
      'selectAppsDesc': 'Укажите, перед какими приложениями показывать паузу',
      'pauseDuration': '60 секунд паузы',
      'pauseDurationDesc': 'Дыхательная анимация и время подумать',
      'continueUsing': 'Продолжайте',
      'continueUsingDesc': 'После паузы — свободный переход в приложение',
      'setupPermissions': 'Настроить разрешения',
      'twoPermissions': 'Нужны два разрешения',
      'twoPermissionsDesc':
          'Без них приложение не сможет отслеживать запуск других приложений',
      'checkPermissions': 'Проверить разрешения',
      'grantBoth': 'Выдайте оба разрешения, чтобы продолжить',
      'batteryTitle': 'Оптимизация батареи',
      'batteryDesc':
          'Чтобы защита работала стабильно, отключите оптимизацию батареи для Mindful Pause. Без этого система может остановить фоновый сервис.',
      'disableBatteryOpt': 'Отключить оптимизацию батареи',
      'disableBatteryOptDesc': 'Нажмите и выберите «Разрешить»',
      'check': 'Проверить',
      'batteryDisabled':
          'Оптимизация батареи отключена — сервис будет работать стабильно',
      'start': 'Начать',
      'skipWarning': 'Можно пропустить, но сервис может быть нестабильным',

      'pauseTitle': 'Сделай паузу',
      'beforeOpening': 'перед открытием {app}',
      'inhale': 'Вдох...',
      'hold': 'Задержка...',
      'exhale': 'Выдох...',
      'wait': 'Подожди...',
      'openApp': 'Открыть {app}',
      'noteHint': 'Зачем ты хочешь это открыть?',

      'notifTitle': 'Mindful Pause',
      'notifText': 'Защита активна · Приложений: {count}',
      'notifChannelName': 'Мониторинг приложений',
      'notifChannelDesc': 'Mindful Pause отслеживает запуск приложений',
      'notifStop': 'Выключить',
    },
  };

  String get _langCode =>
      _localizedValues.containsKey(locale.languageCode)
          ? locale.languageCode
          : 'en';

  String _raw(String key) =>
      _localizedValues[_langCode]?[key] ??
      _localizedValues['en']![key] ??
      key;

  String t(String key, [Map<String, String>? args]) {
    var s = _raw(key);
    args?.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  // Convenience
  String get appTitle => _raw('appTitle');
  String get protectionActive => _raw('protectionActive');
  String get protectionOff => _raw('protectionOff');

  String cooldownLabelShort(int minutes) {
    if (minutes >= 60) return _raw('hour1');
    return t('min', {'n': '$minutes'});
  }

  String cooldownLabelFull(int minutes) {
    if (minutes == 1) return _raw('minute1');
    if (minutes < 5) return t('minutesFew', {'n': '$minutes'});
    if (minutes == 60) return _raw('hour1');
    return t('minutesMany', {'n': '$minutes'});
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ru'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}