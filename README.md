<div align="center">

<img src="docs/logo.jpg" alt="Illusio" width="160"/>

# Illusio

**Лаунчер Space Station 14 на Rust и Flutter**

[![ci](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml/badge.svg)](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/mel0k1/Illusio?sort=semver)](https://github.com/mel0k1/Illusio/releases)

</div>

## Зачем

Официальный лаунчер SS14 написан на C# с Avalonia и выглядит одинаково устаревшим на всех платформах. Illusio переписывает его: логика живёт в Rust, интерфейс - во Flutter. Ядро тестируется отдельно от интерфейса, а анимации и вёрстка ведут себя одинаково на Windows, Linux и macOS.

## Как устроен

- `core` - библиотека на Rust. Статусы серверов и список хаба по протоколу RobustToolbox, вход на центральные серверы SS14, скачивание и обновление клиента (zip-сборки и ACZ-манифесты с дельта-обновлениями), запуск игры. Наружу смотрит короткий C-интерфейс.
- `app` - приложение на Flutter в стиле Material 3 Expressive. Общается с ядром через FFI.
- `loader` - обвязка на C# по мотивам SS14.Loader из официального лаунчера. Поднимает движок из zip, монтирует файлы сервера и моды, применяет Harmony-патчи, запускает игру.

## Возможности

- плавающий док («Главная», «Сервера», «Настройки», «Моды»), тёмная и светлая темы, русский и английский интерфейс;
- «Сервера»: список с основного и дополнительных хабов, поиск, пинг, онлайн, теги, ссылки сервера, фильтры по языку, региону, RP-уровню, возрастному ограничению, вайтлисту и числу игроков;
- «Главная»: избранное с подъемом наверх, прямое подключение по адресу, запуск реплеев content bundle;
- аккаунты: вход на `auth.spacestation14.com` с двухфакторной аутентификацией, несколько сохранённых аккаунтов, гостевой вход, подмена имени, автовозобновление токена;
- «Моды»: zip-оверлеи, DLL-моды с классом `IllusioMod`, сайдлоад игровых модов через ModLoader движка, ресурс-паки, дампер контента сервера;
- «Настройки»: тема, язык, полноэкранный режим, vsync, каталог клиента, кастомные движки, аргументы запуска, дополнительные хабы, логи клиента, очистка кэша;
- SOCKS5-прокси для всего трафика: HTTP-запросы с авторизацией по логину и паролю, игровой UDP через UDP ASSOCIATE, проверка прокси перед запуском игры;
- загрузка клиента: zip по `download_url` с проверкой SHA-256 или ACZ с манифестом по BLAKE2b, блобами и zstd, кэш файлов по хэшу; движок берётся с CDN и проверяется по SHA-256 и подписи Ed25519;
- патчи loader'а: HWID (случайный, фиксированный или привязанный к аккаунту), скрытие loader и модов от детекта, отключение Discord Rich Presence, фильтр удалённых команд, блокировка серверного редиала;
- бэкпорты с гейтами по версии движка и форка, Dynamic PGO, политика конфиденциальности сервера перед первым подключением, обновление лаунчера из GitHub Releases, ссылки `ss14://`;
- готовые сборки под Windows, Linux и macOS.

## Сборка

Нужны установленные Rust и Flutter.

Ядро:
```bash
cd core
cargo build --release
```

Приложение:
```bash
cd app
flutter create . --platforms=windows,linux,macos
flutter pub get
flutter run
```

Собранную библиотеку ядра положите рядом с исполняемым файлом приложения: `libillusio.so` для Linux, `illusio.dll` для Windows, `libillusio.dylib` для macOS.

Для серверов с ACZ рядом с приложением нужен каталог `loader`: его собирает `dotnet publish loader/Illusio.Loader.csproj` (нужен .NET 10 SDK). В готовых сборках из Releases он уже есть.

## Моды

### DLL-моды

Для DLL-мода нужен публичный статический класс `IllusioMod` со статическим методом `Patch`:

```csharp
using HarmonyLib;

public static class IllusioMod
{
    public static string Name = "Мой мод";
    public static string Description = "Что он делает";
    public static bool Preload = true;

    public static void Patch(Harmony harmony)
    {
        harmony.PatchAll(typeof(IllusioMod).Assembly);
    }
}
```

Поле `Preload = true` применяет патчи до загрузки движка, иначе патчи применяются сразу и повторяются после загрузки контентных сборок, если цели ещё не существовали. Ссылаться на `Lib.Harmony` не обязательно: метод можно объявить без параметров, тогда инстанс Harmony создаёт loader.

Сборки без класса `IllusioMod` считаются игровыми модами: loader сайдлоадит их в клиент через ModLoader движка.

### Ресурс-паки

Папки лежат в каталоге `respacks`, открывается из вкладки «Моды». Каждый пак - папка с `meta.json`:

```json
{
  "Name": "HiTech",
  "Description": "Замена текстур в стиле хай-тек",
  "Target": "hitech_fork"
}
```

Внутри - файлы, повторяющие пути контента: `/Textures/...`, `/Audio/...`. Включённые паки подменяют файлы через постфикс на `ResourceManager.ContentFindFiles`. Поле `Target` фильтрует пак по форку сервера, пустое значение - пак для всех.

### Дампер ресурсов

Переключатель во вкладке «Моды». При следующем подключении loader выгружает весь контент сервера в `dumps/<fork_id>` - готовую заготовку ресурс-пака. Дамп и ресурс-паки не работают одновременно.

## Проверки

```bash
cd core
cargo clippy -- -D warnings
cargo test
```

```bash
cd app
flutter analyze
flutter test
```

CI прогоняет оба набора на каждый пуш в main.

## Релизы

```bash
git tag v0.11.2
git push origin v0.11.2
```

GitHub Actions соберёт ядро, loader и приложение под Windows, Linux и macOS, сложит всё в архивы и прикрепит к релизу на странице [Releases](https://github.com/mel0k1/Illusio/releases).

## Лицензия

MIT. Текст лицензии в [LICENSE](LICENSE).

Код в `loader` основан на SS14.Loader и Robust.LoaderApi из официального репозитория [space-wizards/SS14.Launcher](https://github.com/space-wizards/SS14.Launcher) (лицензия MIT, авторство Space Station 14 Contributors) - подробности в [loader/LICENSE.txt](loader/LICENSE.txt).
