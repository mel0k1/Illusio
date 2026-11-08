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

- `core` - библиотека на Rust. Получает статус серверов и данные сборки по протоколу RobustToolbox, входит в аккаунт центральных серверов SS14, скачивает и обновляет клиент, запускает игру. Наружу смотрит короткий C-интерфейс.
- `app` - приложение на Flutter. Общается с ядром через FFI и рисует список серверов, вход в аккаунт, настройки и экран "О приложении".

## Возможности

- статус серверов: игроки, теги, описание;
- авторизация на `auth.spacestation14.com`, поддержка двухфакторной аутентификации, автообновление токена;
- загрузка клиента с сервера: сборка выбирается по `/info`, архив проверяется по SHA-256, повторное подключение переиспользует уже установленную версию;
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
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions соберёт приложение под Windows, Linux и macOS, положит библиотеку ядра внутрь и прикрепит архивы к релизу на странице [Releases](https://github.com/mel0k1/Illusio/releases).

## Лицензия

MIT. Текст лицензии в [LICENSE](LICENSE).
