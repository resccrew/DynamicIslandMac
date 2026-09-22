# DynamicIslandMac

## Описание и цель
Имитация iOS Dynamic Island на macOS: плавающая "остров"-панель под вырезом экрана (notch),
показывающая Now Playing для Spotify/Apple Music, карточку на экране блокировки с синхронизированными
лириками, уведомления о подключении устройств (зарядка, Bluetooth-аудио) и живой статус-пилюлю.
Без сэндбокса, без Developer ID — собирается из исходников, ad-hoc подпись.

## Стек
- Swift 5.9, Swift Package Manager (не Xcode-проект)
- macOS 14+ (`platforms: [.macOS(.v14)]`)
- Только системные фреймворки: AppKit, SwiftUI, Combine, CoreAudio, IOKit
- Единственный внешний сетевой вызов — [LRCLIB](https://lrclib.net) API за синхронными лириками
- Сборка: `./build_app.sh [--install]`

## Архитектура
- `AppDelegate` — точка входа. Держит один `IslandViewModel` (источник истины), `NowPlayingPoller`
  (опрос AppleScript раз в секунду) и `DeviceMonitors` (event-driven, CoreAudio/IOKit).
- `IslandViewModel` раздаёt состояние двум независимым window-контроллерам:
  `IslandWindowController` (панель под вырезом) и `LockScreenWindowController`
  (оверлей поверх экрана блокировки через приватный SkyLight — `SkyLightSpace.swift`).
- `IslandSettings` — синглтон, персистентность через `UserDefaults`, читается напрямую всеми view.
- `NotchShape` — чистый модуль геометрии (суперэллипсы), решён аккуратно, отдельно от остального UI.
- `AppleScriptNowPlaying` — единственный способ читать Spotify/Music (публичного API нет).

### Ключевое договорённое решение (важно не сломать повторно)
`hasContent` (лок-скрин, показывает паузу — как в iOS) и `isIslandVisible` (плавающий остров,
должен скрываться при паузе) — сознательно **разные** свойства в `IslandViewModel`. Причина:
Spotify AppleScript не имеет настоящего "stopped" — `stop` — это просто `pause`, и трек репортит
title бесконечно после паузы. Если `isIslandVisible` смотрит только на `!title.isEmpty` без
`isPlaying`, остров торчит из выреза до перезапуска Spotify. См. `IslandViewModel.swift:84-90`.

## Правила кодирования проекта
- `[weak self]` в замыканиях, таймерах, NotificationCenter-подписках, где self может пережить подписку.
- UI-мутации строго на main thread.
- Сетевые вызовы (LyricsProvider) — graceful fallback на каждом уровне, не throw наружу в UI.
- Не логировать пользовательские данные (названия треков и т.п.) в файлы вне debug-сборки.

## Известные ограничения и риски
- Лайк трека работает только в Apple Music — Spotify не даёт scriptable "like" без OAuth Web API.
- Нет сертификата подписи — Gatekeeper предупреждение на скачанной копии (сборка из исходников это обходит).
- Лок-скрин оверлей и Bluetooth-детали опираются на приватные API (`SkyLightSpace`, `system_profiler`) —
  не документированы, могут сломаться с обновлением macOS.
- **`BluetoothDeviceInfo.run()`** (строка ~24-39): stderr `Pipe()` от `system_profiler` никогда не
  читается — при большом выводе в stderr дочерний процесс может заблокироваться на записи, и
  `waitUntilExit()` повиснет навсегда на background-очереди.

## Текущий статус (на 2026-09-22)
Полный аудит кодовой базы проведён. Общая оценка: архитектурно и по стилю выше среднего для
side-проекта — нет опасных force-unwrap, нет пустых catch/TODO, потоки разведены аккуратно.

Исправлено:
- **Регресс в `IslandViewModel.swift`** — `isPlaying` вернули в `isIslandVisible`, файл совпадает
  с последним коммитом (`git diff` по нему чист).
- **Debug-логирование** в `LockScreenWindowController.log()` обёрнуто в `#if DEBUG` — трек больше
  не пишется в `/tmp/island-lock.log` в release-сборке.
- **Потенциальный deadlock** в `BluetoothDeviceInfo.run()` — неиспользуемый stderr `Pipe()` заменён
  на `FileHandle.nullDevice`, запись туда больше не может заблокировать процесс.
- **README** синхронизирован — убраны упоминания `ClaudeAgentMonitor`/status pill (код удалён
  коммитом `46d9492`, но README не обновляли).
- Билд (`swift build -c debug`) зелёный после всех правок.

Осталось, требует продуктового решения (не тронуто намеренно):
- Мёртвый код: `AudioOutputs.swift` (142 строки, AirPlay-подобный пикер) и
  `IslandViewModel.openPlayer()` реализованы, но нигде не подключены к UI — подключить или удалить?
- Дублирование `formatTime`/`progressFraction`/controls между `IslandView` и `LockScreenView` —
  не баг, но правка в одном месте не подхватится в другом.

## Зоны ответственности агентов в этом проекте
- **Planner** — приоритизация находок аудита, разбивка на фичи/фиксы.
- **Implementer** — фикс регресса в `IslandViewModel`, подключение или удаление мёртвого кода
  (`AudioOutputs`, `openPlayer`), вынос debug-логирования под флаг.
- **Tester** — для этого проекта нет автоматических тестов (SPM executable target без test target);
  проверка вручную через `./build_app.sh` + запуск приложения.
- **Critic** — держит в курсе, что `hasContent` vs `isIslandVisible` разведены намеренно, не давать
  повторно смержить их без веской причины.
- **Documenter** — синхронизировать README с реальным состоянием `Sources/` (сейчас расходится).
- **Security** — приватные API (`SkyLightSpace`, AppleScript) не читают/не пишут чувствительные
  данные за пределами локального логирования — проверять при изменениях в этой области.
