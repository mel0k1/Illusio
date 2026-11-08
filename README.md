<div align="center">

<img src="docs/logo.jpg" alt="Illusio" width="160"/>

# Illusio

**Лаунчер Space Station 14 на Rust и Flutter**

[![ci](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml/badge.svg)](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/mel0k1/Illusio?sort=semver)](https://github.com/mel0k1/Illusio/releases)

</div>

## Зачем

Официальный лаунчер SS14 написан на C# с Avalonia, и его интерфейс выглядит одинаково устаревшим на всех платформах. Illusio - это переписывание: логика переезжает в Rust, интерфейс - во Flutter. От этого две выгоды: ядро тестируется отдельно от интерфейса, а анимации и вёрстка ведут себя одинаково на Windows, Linux и macOS.

## Как устроен

- `core` - библиотека на Rust. Получает статус серверов и список хаба по протоколу RobustToolbox, входит в аккаунт центральных серверов SS14, скачивает и обновляет клиент - как классическими zip-сборками, так и по ACZ-манифестам с дельта-обновлениями, запускает игру. Наружу смотрит короткий C-интерфейс.
- `app` - приложение на Flutter в стиле Material 3 Expressive. Общается с ядром через FFI.
- `loader` - небольшая обвязка на C# по мотивам SS14.Loader из официального лаунчера. Собирается в CI и входит в готовые сборки: она поднимает движок из zip, монтирует сверху файлы сервера и zip-моды и запускает игру.

## Возможности

- плавающий нижний док: «Главная», «Сервера», «Настройки», «Моды»;
- «Главная»: избранные сервера, добавление по адресу и названию, прямое подключение вставкой адреса;
- «Сервера»: живой список с хаба `hub.spacestation14.com`, поиск, онлайн у каждого сервера, описание с тегами, картой и раундом, подключение и добавление в избранное;
- избранные сервера хранятся в конфиге;
- авторизация на `auth.spacestation14.com`, поддержка двухфакторной аутентификации, автообновление токена;
- несколько сохранённых аккаунтов: переключение одним касанием, выход, добавление, ссылка на регистрацию;
- «Моды»: ZIP-архивы из каталога модов включаются переключателем и монтируются в клиент как оверлей при запуске;
- «Настройки»: тема (тёмная/светлая), полноэкранный режим, vsync, скрытие пустых серверов, каталог клиента, аргументы запуска, очистка кэша;
- загрузка клиента с сервера:
  - классические zip-сборки по `download_url` с проверкой SHA-256;
  - серверы с ACZ (Automatic Content Zipper): манифест контента проверяется по BLAKE2b, недостающие файлы докачиваются блобами с zstd, каждый файл кэшируется по хэшу - повторное подключение после обновления сервера качает только изменённое;
  - движок нужной версии берется с `robust-builds.cdn.spacestation14.com` и проверяется по SHA-256 и подписи Ed25519;
- запуск клиента с токеном аккаунта и адресом сервера, как в официальном лаунчере;
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

Готовые архивы собирает workflow `release`. Порядок запуска:

```bash
git tag v0.4.0
git push origin v0.4.0
```

GitHub Actions соберёт ядро, loader и приложение под Windows, Linux и macOS, сложит всё в архивы и прикрепит их к релизу на странице [Releases](https://github.com/mel0k1/Illusio/releases).

## Лицензия

MIT. Текст лицензии в [LICENSE](LICENSE).

Код в `loader` основан на SS14.Loader и Robust.LoaderApi из официального репозитория [space-wizards/SS14.Launcher](https://github.com/space-wizards/SS14.Launcher) (лицензия MIT, авторство Space Station 14 Contributors) - подробности в [loader/LICENSE.txt](loader/LICENSE.txt).
