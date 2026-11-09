import 'package:flutter/material.dart';

class S {
  const S(this.language);

  final String language;

  bool get ru => language != 'en';

  static S of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SB>()?.s ?? const S('ru');

  String get home => ru ? 'Главная' : 'Home';
  String get servers => ru ? 'Сервера' : 'Servers';
  String get settings => ru ? 'Настройки' : 'Settings';
  String get mods => ru ? 'Моды' : 'Mods';
  String get signIn => ru ? 'Войти' : 'Sign in';

  String get homeTitle => home;
  String get homeSubtitle => ru
      ? 'избранные сервера и прямое подключение'
      : 'favorite servers and direct connect';
  String get directTitle => ru ? 'Прямое подключение' : 'Direct connect';
  String get directHint => ru
      ? 'Вставьте адрес сервера — клиент скачается сам при первом подключении.'
      : 'Paste a server address — the client downloads itself on first connect.';
  String get address => ru ? 'Адрес' : 'Address';
  String get play => ru ? 'Играть' : 'Play';
  String get launchReplay => ru ? 'Запустить реплей' : 'Watch replay';
  String get replayTypeLabel => ru ? 'реплеи' : 'replays';
  String get needZipBundle => ru
      ? 'нужен zip-архив content bundle'
      : 'a content bundle zip archive is required';
  String get launchingReplay => ru ? 'Запуск реплея' : 'Replay playback';
  String get favorites => ru ? 'Избранное' : 'Favorites';
  String get add => ru ? 'Добавить' : 'Add';
  String get addServer => ru ? 'Добавить сервер' : 'Add server';
  String get editServer => ru ? 'Изменить сервер' : 'Edit server';
  String get serverName => ru ? 'Название' : 'Name';
  String get serverNameHint =>
      ru ? 'как отобразить в избранном' : 'how it appears in favorites';
  String get serverAddress => ru ? 'Адрес сервера' : 'Server address';
  String get cancel => ru ? 'Отмена' : 'Cancel';
  String get save => ru ? 'Сохранить' : 'Save';
  String get raiseTop => ru ? 'Поднять наверх' : 'Move to top';
  String get edit => ru ? 'Изменить' : 'Edit';
  String get removeFavorite =>
      ru ? 'Убрать из избранного' : 'Remove from favorites';
  String get addFavorite => ru ? 'В избранное' : 'Add to favorites';
  String get emptyFavoritesTitle =>
      ru ? 'Здесь пока пусто' : 'Nothing here yet';
  String get emptyFavoritesHint => ru
      ? 'Добавьте первый сервер или найдите его на вкладке «Сервера».'
      : 'Add your first server or find one on the Servers tab.';
  String get connecting => ru ? 'Подключение' : 'Connecting';
  String get clientStarted => ru ? 'Клиент запущен' : 'Client started';
  String get connectFailed =>
      ru ? 'не удалось подключиться' : 'failed to connect';
  String get hide => ru ? 'Скрыть' : 'Hide';
  String get privacyTitle =>
      ru ? 'Политика конфиденциальности' : 'Privacy policy';
  String privacyBody(String name) => ru
      ? 'Сервер «$name» требует принять свою политику конфиденциальности перед подключением.'
      : 'The server "$name" requires accepting its privacy policy before connecting.';
  String privacyVersion(String version) =>
      ru ? 'Версия: $version' : 'Version: $version';
  String get reject => ru ? 'Отклонить' : 'Decline';
  String get accept => ru ? 'Принять' : 'Accept';

  String get serversTitle => servers;
  String get serversSubtitle =>
      ru ? 'живой список хаба и фильтры' : 'live hub list and filters';
  String get search => ru ? 'Поиск' : 'Search';
  String get searchHint =>
      ru ? 'имя или адрес сервера' : 'server name or address';
  String get refresh => ru ? 'Обновить' : 'Refresh';
  String get retry => ru ? 'Повторить' : 'Retry';
  String get filters => ru ? 'Фильтры' : 'Filters';
  String get filtersTitle => ru ? 'Фильтры серверов' : 'Server filters';
  String get reset => ru ? 'Сбросить' : 'Reset';
  String get done => ru ? 'Готово' : 'Done';
  String get filtersHint => ru
      ? 'внутри категории фильтры складываются «или», между категориями — «и»'
      : 'within a category filters combine with "or", across categories — "and"';
  String get playersFrom => ru ? 'Игроков от' : 'Players from';
  String get playersTo => ru ? 'Игроков до' : 'Players to';
  String get hideFullServers =>
      ru ? 'Скрывать полные сервера' : 'Hide full servers';
  String get loadingList =>
      ru ? 'Получаем список серверов' : 'Fetching server list';
  String get hubUnavailable => ru ? 'Хаб недоступен' : 'Hub unavailable';
  String get listNotUpdated => ru ? 'список не обновлён' : 'list not refreshed';
  String get connect => ru ? 'Подключиться' : 'Connect';
  String get serverNotResponding =>
      ru ? 'сервер не отвечает' : 'server is not responding';
  String get pingUnmeasured => ru ? 'пинг не измерен' : 'ping not measured';
  String pingLabel(String label) => ru ? 'пинг $label' : 'ping $label';
  String serversCount(int visible, int total, int online) => ru
      ? '$visible из $total ${_serversWord(total)} · $online ${_playersWord(online)} онлайн'
      : '$visible of $total servers · $online players online';
  String playersOf(int count, int max) => ru
      ? max <= 0
            ? '$count ${_playersWord(count)}'
            : '$count / $max ${_playersWord(max)}'
      : max <= 0
      ? '$count players'
      : '$count / $max players';
  String get round => ru ? 'Раунд' : 'Round';
  String get inRound => ru ? 'В раунде' : 'In round';
  String get afterRound => ru ? 'После раунда' : 'After round';
  String get lobby => ru ? 'Лобби' : 'Lobby';
  String get serverFallback => ru ? 'Сервер' : 'Server';
  String get langPrefix => ru ? 'Язык: ' : 'Language: ';
  String get regionPrefix => ru ? 'Регион: ' : 'Region: ';
  String get whitelist => ru ? 'Вайтлист' : 'Whitelist';
  String get rpNone => ru ? 'нет' : 'none';
  String get rpLow => ru ? 'лёгкий' : 'light';
  String get rpMedium => ru ? 'средний' : 'medium';
  String get rpHigh => ru ? 'тяжёлый' : 'heavy';
  String detailsFailed(String error) => ru
      ? 'Не удалось получить описание: $error'
      : 'Failed to load description: $error';
  String infoFailed(String error) => ru
      ? 'не удалось получить /info: $error'
      : 'failed to fetch /info: $error';

  static const regionNames = {
    'eu_west': 'Европа (запад)',
    'eu_east': 'Европа (восток)',
    'na_west': 'Северная Америка (запад)',
    'na_east': 'Северная Америка (восток)',
    'na_central': 'Северная Америка (центр)',
    'sa_central': 'Центральная Америка',
    'asia_north': 'Азия (север)',
    'asia_east': 'Азия (восток)',
    'asia_se': 'Азия (юго-восток)',
    'oceania': 'Океания',
  };

  String regionName(String value) =>
      ru ? regionNames[value.toLowerCase()] ?? value : value;

  String hubPrefix(String hub) => ru ? 'хаб $hub' : 'hub $hub';

  String _serversWord(int count) {
    final last = count % 10;
    final tens = count % 100;
    if (last == 1 && tens != 11) return 'сервер';
    if (last >= 2 && last <= 4 && (tens < 12 || tens > 14)) return 'сервера';
    return 'серверов';
  }

  String _playersWord(int count) {
    final last = count % 10;
    final tens = count % 100;
    if (last == 1 && tens != 11) return 'игрок';
    if (last >= 2 && last <= 4 && (tens < 12 || tens > 14)) return 'игрока';
    return 'игроков';
  }

  String get settingsTitle => settings;
  String get settingsSubtitle => ru
      ? 'внешний вид, поведение и клиент игры'
      : 'appearance, behavior and game client';
  String get appearance => ru ? 'Внешний вид' : 'Appearance';
  String get theme => ru ? 'Тема' : 'Theme';
  String get themeHint =>
      ru ? 'тёмная включена по умолчанию' : 'dark is enabled by default';
  String get themeDark => ru ? 'Тёмная' : 'Dark';
  String get themeLight => ru ? 'Светлая' : 'Light';
  String get themeDarkRed => ru ? 'Тёмно-красная' : 'Dark red';
  String get themeDarkPurple => ru ? 'Тёмно-фиолетовая' : 'Dark purple';
  String get themeMidnightBlue => ru ? 'Полночный синий' : 'Midnight blue';
  String get themeEmeraldDusk => ru ? 'Изумрудные сумерки' : 'Emerald dusk';
  String get themeCopperNight => ru ? 'Медная ночь' : 'Copper night';
  String get languageLabel => ru ? 'Язык' : 'Language';
  String get languageHint =>
      ru ? 'интерфейс приложения и подписи' : 'app interface and labels';
  String get gameSection => ru ? 'Игра' : 'Game';
  String get fullscreen => ru ? 'Полноэкранный режим' : 'Fullscreen';
  String get serverListSection => ru ? 'Список серверов' : 'Server list';
  String get hideEmptyServers =>
      ru ? 'Скрывать пустые сервера' : 'Hide empty servers';
  String get hideEmptyHint => ru
      ? 'сервера без игроков не отображаются'
      : 'servers without players are hidden';
  String get hideFullHint =>
      ru ? 'у них заняты все слоты' : 'all slots are taken';
  String get hubs => ru ? 'Хабы' : 'Hubs';
  String get hubsHint => ru
      ? 'основной хаб SS14 подключён всегда, ниже — дополнительные'
      : 'the main SS14 hub is always on, extras go below';
  String get addHub => ru ? 'Добавить хаб' : 'Add hub';
  String get removeHub => ru ? 'Убрать хаб' : 'Remove hub';
  String get hubAddress => ru ? 'Адрес хаба' : 'Hub address';
  String get clientSection => ru ? 'Клиент' : 'Client';
  String get installDir => ru ? 'Каталог для клиента' : 'Client directory';
  String get installDirHint => ru
      ? 'по умолчанию — системный каталог данных'
      : 'defaults to the system data directory';
  String get launchArgs => ru ? 'Аргументы запуска' : 'Launch arguments';
  String get clientLogs => ru ? 'Логи клиента' : 'Client logs';
  String get clientLogsHint => ru
      ? 'stdout и stderr пишутся в каталог logs'
      : 'stdout and stderr go to the logs directory';
  String get clientSaved =>
      ru ? 'Настройки клиента сохранены' : 'Client settings saved';
  String get accountSection => ru ? 'Аккаунт' : 'Account';
  String get guest => ru ? 'Гость' : 'Guest';
  String get guestName => ru ? 'Имя гостя' : 'Guest name';
  String get guestNameHint => ru
      ? 'под каким именем заходить без аккаунта'
      : 'the name used without an account';
  String get overrideName => ru ? 'Подменить имя' : 'Override name';
  String get overrideNameHint =>
      ru ? 'имя вместо логина аккаунта' : 'a name instead of the account login';
  String get accountSaved =>
      ru ? 'Настройки аккаунта сохранены' : 'Account settings saved';
  String get manageAccounts => ru ? 'Управление аккаунтами' : 'Manage accounts';
  String accountsHintSignedInOf(int n) =>
      ru ? '$n сохранённых аккаунтов' : '$n saved account${n == 1 ? '' : 's'}';
  String get accountHintGuest => ru
      ? 'войдите, чтобы играть на серверах с аутентификацией'
      : 'sign in to play on servers with authentication';
  String get diagnostics => ru ? 'Диагностика' : 'Diagnostics';
  String get configStored => ru ? 'Конфиг хранится в:' : 'Config stored in:';
  String get pathUndefined => ru ? 'каталог не определён' : 'directory unknown';
  String get loadingDots => ru ? 'загружаем…' : 'loading…';
  String get modsDirOpen => ru ? 'Каталог модов' : 'Mods directory';
  String get logsDirOpen => ru ? 'Каталог логов' : 'Logs directory';
  String get clearCache => ru ? 'Очистить кэш' : 'Clear cache';
  String get cacheCleared =>
      ru ? 'Кэш загрузок очищен' : 'Download cache cleared';
  String get cacheFailed =>
      ru ? 'Не удалось очистить кэш' : 'Failed to clear cache';
  String get coreLabel => ru ? 'ядро' : 'core';

  String get proxySection => ru ? 'Прокси' : 'Proxy';
  String get proxyProfiles => ru ? 'Профили' : 'Profiles';
  String get proxyProfilesHint => ru
      ? 'выберите активный профиль SOCKS5'
      : 'pick the active SOCKS5 profile';
  String get addProxyProfile => ru ? 'Добавить профиль' : 'Add profile';
  String get editProxyProfile => ru ? 'Изменить профиль' : 'Edit profile';
  String get deleteProxyProfile => ru ? 'Удалить профиль' : 'Delete profile';
  String get proxyProfileName => ru ? 'Название' : 'Name';
  String get proxyProfileNameHint =>
      ru ? 'например, рабочий SOCKS5' : 'for example, office SOCKS5';
  String get proxyNoProfiles => ru
      ? 'профилей пока нет — добавьте первый'
      : 'no profiles yet — add the first one';
  String get proxyEnable =>
      ru ? 'Прокси для лаунчера' : 'Proxy for the launcher';
  String get proxyEnableHint => ru
      ? 'весь трафик лаунчера идёт через SOCKS5'
      : 'all launcher traffic goes through SOCKS5';
  String get proxyUpdatesEnable =>
      ru ? 'Прокси для обновлений' : 'Proxy for updates';
  String get proxyUpdatesHint => ru
      ? 'launcher-data и GitHub идут через SOCKS5'
      : 'launcher-data and GitHub go through SOCKS5';
  String get proxyRegionEnable =>
      ru ? 'Обход региональной блокировки' : 'Region block bypass';
  String get proxyRegionHint => ru
      ? 'CDN сборок движка идёт через прокси'
      : 'the engine builds CDN goes through the proxy';
  String get proxyHost => ru ? 'Хост прокси' : 'Proxy host';
  String get proxyPort => ru ? 'Порт прокси' : 'Proxy port';
  String get proxyUser => ru ? 'Логин прокси' : 'Proxy username';
  String get proxyUserHint => ru ? 'необязательно' : 'optional';
  String get proxyPassword => ru ? 'Пароль прокси' : 'Proxy password';
  String get proxyUdp => ru ? 'UDP-релей игры' : 'Game UDP relay';
  String get proxyUdpHint => ru
      ? 'игровой трафик идёт через UDP ASSOCIATE прокси'
      : 'game traffic goes through the proxy UDP ASSOCIATE';
  String get proxyApply =>
      ru ? 'Прокси для клиента игры' : 'Proxy for the game client';
  String get proxyApplyHint => ru
      ? 'переменные ALL_PROXY и HTTP_PROXY передаются игре'
      : 'ALL_PROXY and HTTP_PROXY variables are passed to the game';
  String get proxyTest => ru ? 'Проверить' : 'Test';
  String get proxyTesting => ru ? 'Проверяем…' : 'Testing…';
  String proxyOk(int rtt) =>
      ru ? 'прокси работает, $rtt мс' : 'proxy works, $rtt ms';
  String proxyOkUdp(int rtt) => ru
      ? 'прокси работает, $rtt мс, UDP доступен'
      : 'proxy works, $rtt ms, UDP available';
  String get proxySaved =>
      ru ? 'Настройки прокси сохранены' : 'Proxy settings saved';
  String get proxyNoUdp => ru
      ? 'прокси работает, но UDP не поддерживается'
      : 'proxy works but UDP is not supported';
  String get proxyUnavailableTitle =>
      ru ? 'Прокси недоступен' : 'Proxy unavailable';
  String proxyUnavailableBody(String error) => ru
      ? 'Проверка SOCKS5 не прошла: $error. Продолжить без прокси? Прокси включится снова при изменении настроек.'
      : 'The SOCKS5 probe failed: $error. Continue without the proxy? It turns back on when settings change.';
  String get proxyContinueNoProxy =>
      ru ? 'Продолжить без прокси' : 'Continue without proxy';
  String get proxyKeepTrying => ru ? 'Оставить как есть' : 'Keep as is';
  String get proxySessionOffNotice => ru
      ? 'Прокси отключён до изменения настроек'
      : 'Proxy disabled until settings change';

  String get updatesSection => ru ? 'Обновления лаунчера' : 'Launcher updates';
  String currentVersion(String version) =>
      ru ? 'Текущая версия: $version' : 'Current version: $version';
  String get checkUpdates => ru ? 'Проверить обновления' : 'Check for updates';
  String get checkingUpdates => ru ? 'Проверяем…' : 'Checking…';
  String updateAvailable(String version) =>
      ru ? 'Доступна версия $version' : 'Version $version available';
  String get updateDownload =>
      ru ? 'Скачать и установить' : 'Download and install';
  String get updateDownloading => ru ? 'Скачиваем…' : 'Downloading…';
  String get updateAppliedText => ru
      ? 'Обновление скачано и установится при выходе из лаунчера'
      : 'The update is downloaded and applies when the launcher exits';
  String get restartNow => ru ? 'Закрыть и обновить' : 'Exit and update';
  String get updateLatest =>
      ru ? 'У вас последняя версия' : 'You are on the latest version';
  String updateFailed(String error) =>
      ru ? 'Ошибка обновления: $error' : 'Update failed: $error';
  String get autoUpdateLabel =>
      ru ? 'Обновлять автоматически' : 'Update automatically';
  String get autoUpdateHint => ru
      ? 'скачивать новые версии при запуске'
      : 'download new versions at startup';
  String get prefetchLabel =>
      ru ? 'Предзагрузка избранного' : 'Prefetch favorites';
  String get prefetchHint => ru
      ? 'обновлять сборки избранных серверов в фоне'
      : 'keep favorite server builds up to date in background';

  String get safetySection => ru ? 'Безопасность' : 'Safety';
  String get patchRpcLabel =>
      ru ? 'Отключить Discord RPC' : 'Disable Discord RPC';
  String get patchRpcHint => ru
      ? 'клиент не пишет статус в Discord'
      : 'the client stops updating Discord presence';
  String get patchJamLabel => ru ? 'Блокировать редиал' : 'Jam redials';
  String get patchJamHint => ru
      ? 'клиент не переподключается на другой сервер по команде'
      : 'the client ignores server-command redirects';
  String get patchBlackholeLabel =>
      ru ? 'Фильтр удалённых команд' : 'Remote command filter';
  String get patchBlackholeHint => ru
      ? 'сервер не может выполнять произвольные консольные команды, чат разрешён'
      : 'the server cannot run arbitrary console commands, chat stays allowed';
  String get hideLevelLabel =>
      ru ? 'Скрытие патчей (Stealth)' : 'Patch stealth';
  String get hideLevelHint => ru
      ? 'скрывает загрузчик, Harmony и моды от рефлексии игры; чем выше уровень, тем глубже скрытие'
      : 'hides the loader, Harmony and mods from game reflection; higher levels hide deeper';
  String hideLevelName(int level) {
    if (ru) {
      return switch (level) {
        0 => 'Выключено',
        1 => 'Дуплицит — скрыт только загрузчик',
        2 => 'Обычный',
        3 => 'Усиленный',
        _ => 'Максимальный',
      };
    }
    return switch (level) {
      0 => 'Disabled',
      1 => 'Duplicit — loader only',
      2 => 'Normal',
      3 => 'Explicit',
      _ => 'Unconditional',
    };
  }

  String get hwidModeLabel => ru ? 'HWID' : 'HWID';
  String get hwidModeHint => ru
      ? 'что отправлять серверу вместо реального идентификатора железа'
      : 'what to send to servers instead of the real hardware id';
  String hwidModeName(String mode) {
    if (ru) {
      return switch (mode) {
        'random' => 'Случайный при каждом запуске',
        'fixed' => 'Фиксированный',
        'account' => 'Свой для каждого аккаунта',
        _ => 'Выключено',
      };
    }
    return switch (mode) {
      'random' => 'Random on every launch',
      'fixed' => 'Fixed value',
      'account' => 'Bound to each account',
      _ => 'Disabled',
    };
  }

  String get hwidValueLabel => ru ? 'Значение HWID (hex)' : 'HWID value (hex)';
  String get hwidValueHint =>
      ru ? 'цифры 0-9 и буквы a-f, пусто — случайный' : 'digits 0-9 and a-f, empty means random';
  String get hwidInvalid => ru ? 'некорректный hex' : 'invalid hex';
  String get hwidGenerate => ru ? 'Сгенерировать' : 'Generate';
  String get hwidOptoutLabel =>
      ru ? 'Отключить HWID2' : 'Disable HWID2';
  String get hwidOptoutHint => ru
      ? 'сообщить серверу, что второй идентификатор железа не используется'
      : 'tell the server the second hardware id is not in use';
  String get pgoLabel => ru ? 'Dynamic PGO' : 'Dynamic PGO';
  String get pgoHint => ru
      ? 'динамическая компиляция .NET: заметный прирост FPS без минусов'
      : 'dynamic .NET compilation: a noticeable FPS boost with no downsides';

  String get modsTitle => mods;
  String get modsSubtitle => ru
      ? 'ZIP-оверлеи, DLL-патчи, игровые моды и ресурс-паки'
      : 'ZIP overlays, DLL patches, game mods and resource packs';
  String modsCountLine(int total, int enabled) => ru
      ? '$total ${_filesWord(total)} · $enabled включено'
      : '$total file${total == 1 ? '' : 's'} · $enabled enabled';
  String _filesWord(int count) {
    final last = count % 10;
    final tens = count % 100;
    if (last == 1 && tens != 11) return 'файл';
    if (last >= 2 && last <= 4 && (tens < 12 || tens > 14)) return 'файла';
    return 'файлов';
  }

  String get howItWorks => ru ? 'Как это работает' : 'How it works';
  String get zipHowText => ru
      ? 'Положите ZIP-архивы в каталог модов и включите нужные. Они монтируются в клиент как оверлей при запуске. Отключение вернёт оригинальные ресурсы.'
      : 'Drop ZIP archives into the mods directory and enable the ones you need. They mount into the client as an overlay on launch. Disabling restores original resources.';
  String get dllHowText => ru
      ? 'DLL-сборки с классом IllusioMod применяются к клиенту через Harmony: статический метод Patch(Harmony) вызывается при запуске. Поле public static bool Preload = true применяет патчи до загрузки движка. Отключённые сборки не загружаются вовсе.'
      : 'DLL builds with an IllusioMod class are applied to the client through Harmony: the static Patch(Harmony) method is invoked at launch. A public static bool Preload = true field applies patches before the engine boots. Disabled builds are not loaded at all.';
  String get subverterHowText => ru
      ? 'Игровые моды без класса IllusioMod подгружаются через ModLoader движка — как моды самого сервера. Они видят игровые системы и не нуждаются в Harmony.'
      : 'Game mods without an IllusioMod class are sideloaded through the engine ModLoader — just like server-side mods. They see game systems and do not need Harmony.';
  String get respackHowText => ru
      ? 'Ресурс-паки — папки с meta.json (поля Name, Description, Target) и файлами, повторяющими пути контента: /Textures, /Audio и так далее. Включённые файлы подменяют оригиналы по путям.'
      : 'Resource packs are folders with a meta.json (Name, Description, Target fields) and files mirroring content paths: /Textures, /Audio and so on. Enabled files replace the originals by path.';
  String get dumperHowText => ru
      ? 'Дампер выгружает весь контент сервера в папку dumps при следующем подключении — готовая заготовка ресурс-пака для вашего форка.'
      : 'The dumper exports all server content into the dumps folder on next connect — a ready-made resource pack stub for your fork.';
  String get openFolder => ru ? 'Открыть папку' : 'Open folder';
  String get folderOpened => ru
      ? 'Каталог открыт — положите файлы туда'
      : 'Directory opened — put files there';
  String get modsEmptyTitle => ru ? 'Модов пока нет' : 'No mods yet';
  String get modsEmptyHint => ru
      ? 'Скачайте мод, откройте папку модов и положите файл туда, затем нажмите «Обновить».'
      : 'Download a mod, open the mods directory, drop the file there and press "Refresh".';
  String get zipSection => ru ? 'ZIP-оверлеи' : 'ZIP overlays';
  String get dllSection => ru ? 'DLL-патчи' : 'DLL patches';
  String get subverterSection =>
      ru ? 'Игровые моды (Subverter)' : 'Game mods (Subverter)';
  String get resPacksSection => ru ? 'Ресурс-паки' : 'Resource packs';
  String get dumperSection => ru ? 'Дампер ресурсов' : 'Resource dumper';
  String get modEnabled => ru ? 'включён' : 'enabled';
  String get modDisabled => ru ? 'выключен' : 'disabled';
  String get dllNoMarker => ru
      ? 'без класса IllusioMod — будет сайдлоаден как игровой мод'
      : 'no IllusioMod class — will be sideloaded as a game mod';
  String get preloadBadge => ru ? 'препатч' : 'preload';
  String get gameModLabel => ru ? 'игровой мод' : 'game mod';
  String resPackTarget(String target) =>
      ru ? 'форк: $target' : 'target: $target';
  String resPackFiles(int count) => ru
      ? '$count ${_filesWord(count)}'
      : '$count file${count == 1 ? '' : 's'}';
  String get resPackInvalid =>
      ru ? 'нет или битый meta.json' : 'missing or broken meta.json';
  String get resPacksEmpty => ru
      ? 'Создайте папку пакета в каталоге respacks и положите туда meta.json с полями Name, Description, Target и файлы контента.'
      : 'Create a pack folder inside the respacks directory and put a meta.json with Name, Description, Target fields plus content files there.';
  String get dumperOn => ru
      ? 'Весь контент сервера будет выгружен при следующем подключении'
      : 'All server content will be dumped on next connect';
  String get dumperOff => ru
      ? 'Выгрузка выключена — включите перед подключением к серверу'
      : 'Dumping is off — enable it before connecting to a server';
  String get openDumps => ru ? 'Открыть dumps' : 'Open dumps';
  String get openResPacks => ru ? 'Открыть respacks' : 'Open respacks';

  String get loginTitle => ru ? 'Вход в аккаунт SS14' : 'SS14 account sign-in';
  String get loginHint => ru
      ? 'Тот же аккаунт, что и на сайте spacestation14.io'
      : 'The same account as on spacestation14.io';
  String get username => ru ? 'Логин' : 'Username';
  String get password => ru ? 'Пароль' : 'Password';
  String get tfaCode => ru
      ? 'Код двухфакторной аутентификации'
      : 'Two-factor authentication code';
  String get login => ru ? 'Войти' : 'Sign in';
  String get back => ru ? 'Назад' : 'Back';
  String get forgotPassword => ru ? 'Забыли пароль?' : 'Forgot password?';
  String get resendEmail => ru ? 'Повторить письмо' : 'Resend email';
  String get manageOnSite =>
      ru ? 'Управление аккаунтом на сайте' : 'Manage account on the site';
  String get enterCredentials =>
      ru ? 'Введите логин и пароль' : 'Enter username and password';
  String get loginFailed => ru ? 'вход не удался' : 'sign-in failed';
  String get openRegisterPage =>
      ru ? 'Открываем страницу регистрации' : 'Opening the registration page';
  String get createAccount => ru ? 'Создать аккаунт' : 'Create account';
  String get loginAsGuest => ru ? 'Войти как гость' : 'Sign in as guest';
  String get guestSignedIn => ru ? 'Вошли как гость' : 'Signed in as guest';
  String get addAccount => ru ? 'Добавить аккаунт' : 'Add account';
  String get switchAccount => ru ? 'Сменить аккаунт' : 'Switch account';
  String get savedAccount => ru ? 'сохранённый аккаунт' : 'saved account';
  String get loggedOut => ru ? 'Вы вышли из аккаунта' : 'You signed out';
  String get logout => ru ? 'Выйти' : 'Sign out';
  String sessionUntil(String time) =>
      ru ? 'Сессия до $time' : 'Session until $time';
  String accountSwitched(String name) =>
      ru ? 'Аккаунт: $name' : 'Account: $name';

  String get phaseServerData =>
      ru ? 'Получаем данные сервера' : 'Fetching server data';
  String get phaseEngine => ru ? 'Загружаем движок' : 'Downloading engine';
  String get phaseClient => ru ? 'Загружаем клиент' : 'Downloading client';
  String get phaseExtract => ru ? 'Распаковываем' : 'Extracting';
  String get phaseReady => ru ? 'Клиент готов' : 'Client ready';
  String get busyRequest =>
      ru ? 'запрос уже выполняется' : 'a request is already running';
  String get authIncomplete => ru
      ? 'сервер авторизации вернул неполный ответ'
      : 'the auth server returned an incomplete response';
  String get authFailed =>
      ru ? 'авторизация не удалась' : 'authentication failed';
  String get downloadStartFailed =>
      ru ? 'не удалось начать загрузку' : 'failed to start download';
  String get connectBusy =>
      ru ? 'подключение уже идёт' : 'a connection is already in progress';

  String ms(int value) => ru ? '$value мс' : '$value ms';

  String formatBytes(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ'];
    const unitsEn = ['B', 'KB', 'MB', 'GB'];
    final chosen = ru ? units : unitsEn;
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < chosen.length - 1) {
      value /= 1024;
      unit++;
    }
    final shown = value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(value >= 10 ? 1 : 2);
    return '$shown ${chosen[unit]}';
  }

  String get enginesSection =>
      ru ? 'Кастомные движки' : 'Custom engines';
  String get enginesHint => ru
      ? 'свой движок вместо CDN: zip или папка, метаданные в engine.json'
      : 'your own engine instead of the CDN: zip or folder, metadata in engine.json';
  String get enginesStandard =>
      ru ? 'Стандартный (с CDN)' : 'Standard (from CDN)';
  String get enginesImportZip =>
      ru ? 'Импорт zip' : 'Import zip';
  String get enginesImportFolder =>
      ru ? 'Импорт папки' : 'Import folder';
  String get enginesImporting =>
      ru ? 'Импортируем…' : 'Importing…';
  String get enginesEmpty => ru
      ? 'своих движков пока нет'
      : 'no custom engines yet';
  String engineVersioned(String version) =>
      ru ? 'версия $version' : 'version $version';
  String get enginesDelete => ru ? 'Удалить движок' : 'Delete engine';
  String enginesFailed(String error) =>
      ru ? 'Ошибка движков: $error' : 'Engine error: $error';
  String get backportsLabel => ru ? 'Бэкпорты' : 'Backports';
  String get backportsHint => ru
      ? 'версионно-гейтед патчи: применяются только к совместимым версиям движка и форка'
      : 'version-gated patches: applied only to compatible engine and fork versions';
  String get backportsNoAnyLabel =>
      ru ? 'Отключить Any-бэкпорты' : 'Disable Any-backports';
  String get backportsNoAnyHint => ru
      ? 'применять только бэкпорты с точной версией или диапазоном'
      : 'apply only backports pinned to an exact version or range';
  String get rpcFakeLabel =>
      ru ? 'Подмена ника в Discord' : 'Fake Discord name';
  String get rpcFakeHint => ru
      ? 'Discord Rich Presence показывает выбранное имя вместо реального'
      : 'Discord Rich Presence shows the chosen name instead of the real one';
  String get rpcFakeNameLabel =>
      ru ? 'Имя для Discord' : 'Discord name';
  String get proxyGuardTitle =>
      ru ? 'Прокси не отвечает' : 'Proxy is not responding';
  String proxyGuardBody(String error) => ru
      ? 'Игра должна идти через прокси, но он не отвечает: $error. Запустить без прокси?'
      : 'The game is routed through the proxy, but it is not responding: $error. Launch without the proxy?';
  String get proxyGuardContinue =>
      ru ? 'Запустить без прокси' : 'Launch without proxy';
  String get proxyGuardCancel => ru ? 'Отмена' : 'Cancel';
  String get proxyGuardLabel =>
      ru ? 'Проверять прокси перед запуском' : 'Probe proxy before launch';
  String get proxyGuardHint => ru
      ? 'если прокси мёртв, лаунчер предложит прямое подключение'
      : 'if the proxy is dead the launcher offers a direct launch';
  String get proxyGuardBlocked => ru
      ? 'запуск остановлен: прокси не отвечает'
      : 'launch stopped: proxy is not responding';
}

class SB extends InheritedWidget {
  const SB({super.key, required this.s, required super.child});

  final S s;

  @override
  bool updateShouldNotify(SB oldWidget) => oldWidget.s.language != s.language;
}
