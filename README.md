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

- `core` - библиотека на Rust. Получает статус серверов и данные сборки по протоколу RobustToolbox, входит в аккаунт центральных серверов SS14, скачивает и обновляет клиент - как классическими zip-сборками, так и по ACZ-манифестам с дельта-обновлениями, запускает игру. Наружу смотрит короткий C-интерфейс.
- `app` - приложение на Flutter. Общается с ядром через FFI и рисует список серверов, вход в аккаунт, настройки и экран "О приложении".
- `loader` - небольшая обвязка на C# по мотивам SS14.Loader из официального лаунчера. Собирается в CI и входит в готовые сборки: она поднимает движок из zip, монтирует сверху файлы сервера и запускает игру.

## Возможности

- статус серверов: игроки, теги, описание;
- авторизация на `auth.spacestation14.com`, поддержка двухфакторной аутентификации, автообновление токена;
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
git tag v0.3.0
git push origin v0.3.0
```

GitHub Actions соберёт ядро, loader и приложение под Windows, Linux и macOS, сложит всё в архивы и прикрепит их к релизу на странице [Releases](https://github.com/mel0k1/Illusio/releases).

## Лицензия

MIT. Текст лицензии в [LICENSE](LICENSE).

Код в `loader` основан на SS14.Loader и Robust.LoaderApi из официального репозитория [space-wizards/SS14.Launcher](https://github.com/space-wizards/SS14.Launcher) (лицензия MIT, авторство Space Station 14 Contributors) - подробности в [loader/LICENSE.txt](loader/LICENSE.txt).
