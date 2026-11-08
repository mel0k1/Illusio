<div align="center">

<img src="docs/logo.jpg" alt="Illusio" width="160"/>

# Illusio

**Лаунчер Space Station 14 на Rust и Flutter**

[![ci](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml/badge.svg)](https://github.com/mel0k1/Illusio/actions/workflows/ci.yml)

</div>

## Зачем

Официальный лаунчер SS14 написан на C# с Avalonia, и его интерфейс выглядит одинаково устаревшим на всех платформах. Illusio - это переписывание: логика переезжает в Rust, интерфейс - во Flutter с Material 3 Expressive. От этого две выгоды: ядро тестируется отдельно от интерфейса, а анимации и вёрстка ведут себя одинаково на Windows, Linux и macOS.

## Как устроен

- `core` - библиотека на Rust. Забирает статус серверов по протоколу RobustToolbox, хранит конфигурацию, запускает клиент. Наружу смотрит короткий C-интерфейс.
- `app` - приложение на Flutter. Общается с ядром через FFI и рисует список серверов, настройки и экран "О приложении".

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

## Дорожная карта

- [ ] загрузка и обновление клиента с серверов
- [ ] авторизация на центральных серверах SS14
- [ ] новости и правила сервера внутри лаунчера
- [ ] готовые сборки под Windows, Linux и macOS

## Лицензия

MIT. Текст лицензии в [LICENSE](LICENSE).
