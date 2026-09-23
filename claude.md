# DynamicIslandMac

## Описание и цель
Имитация iOS Dynamic Island на macOS: плавающая "остров"-панель под вырезом экрана (notch),
показывающая Now Playing для ЛЮБОГО источника (Spotify/Music, вкладка браузера с видео/аудио —
YouTube, SoundCloud, Twitch и т.д. в Chrome/Safari/Arc/Firefox/Яндекс, любое медиа-приложение),
идущие звонки (Telegram, FaceTime, Zoom, Discord, Meet в браузере …), карточку на экране блокировки с синхронизированными
лириками, уведомления о подключении устройств (зарядка, Bluetooth-аудио) и живой статус-пилюлю.
Без сэндбокса, без Developer ID — собирается из исходников, ad-hoc подпись.

## Стек
- Swift 5.9, Swift Package Manager (не Xcode-проект)
- macOS 14+ (`platforms: [.macOS(.v14)]`)
- Системные фреймворки: AppKit, SwiftUI, Combine, CoreAudio, CoreMediaIO, IOKit
- Вендорный `Vendor/mediaremote-adapter` (BSD-3, исходники, собирается clang'ом в `build_app.sh`)
  + системный `/usr/bin/perl` — единственный путь к системному Now Playing, см. ниже
- Единственный внешний сетевой вызов — [LRCLIB](https://lrclib.net) API за синхронными лириками
- Сборка: `./build_app.sh [--install]`

## Архитектура
- `AppDelegate` — точка входа. Держит один `IslandViewModel` (источник истины), `NowPlayingPoller`
  (координатор Now Playing), `CallMonitor` (звонки) и, только в DEBUG, `DebugControlServer` (см. раздел про MCP).
- `IslandViewModel` раздаёt состояние двум независимым window-контроллерам:
  `IslandWindowController` (панель под вырезом) и `LockScreenWindowController`
  (оверлей поверх экрана блокировки через приватный SkyLight — `SkyLightSpace.swift`).
- `IslandSettings` — синглтон, персистентность через `UserDefaults`, читается напрямую всеми view.
- `NotchShape` — чистый модуль геометрии (суперэллипсы), решён аккуратно, отдельно от остального UI.
- `SystemNowPlaying` — системный Now Playing через mediaremote-adapter (стрим JSON, event-driven).
  `AppleScriptNowPlaying` — fallback для Spotify/Music, если адаптер недоступен (`swift run` без бандла)
  или умер 3 раза подряд. Команды play/pause/next/prev идут в активный источник через `model.player`.

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

- `AudioOutputs.showPicker()` и `IslandViewModel.openPlayer()` подключены к `controlsRow` в
  `IslandView` (кнопки по бокам от transport-контролов). Сознательно не продублированы в
  `LockScreenView` — обе фичи не имеют смысла за экраном блокировки, см. коммит
  `feat/wire-audio-output-and-open-player`.

- **Верхний concave fillet острова проверен живым скриншотом+пиксельным сканом — рендерится
  корректно** (леворасположенная граница чёрной фигуры монотонно сдвигается вправо на y=0..fillet,
  ~18px сдвиг на 13pt при 2x retina, подтверждено также утрированным fillet=60 — явная кривая).
  Первоначальное подозрение на баг (плоский угол 90° в одном скриншоте) не воспроизвелось при
  повторном аккуратном тесте — похоже на разовый артефакт захвата экрана (не тот Space/момент), а
  не дефект кода. Изменений в `NotchShape.swift`/`IslandSettings.swift` не потребовалось.
- **Пауза теперь плавно затухает (opacity fade ~0.35s ease-out)**, а не резко пропадает —
  `IslandView.swift`, `island`-modifier `.opacity(model.state == .hidden ? 0 : 1)` с отдельной
  `.animation` независимой от spring-анимации размера рамки. Подтверждено живой серией скриншотов:
  чёткий промежуточный полупрозрачный кадр между "воспроизводится" и "скрыт", не мгновенный cut.
  Известный некритичный краевой случай: если реальный курсор мыши в момент паузы находится прямо
  над островом, существующий hover-tracking механизм (`pointerIsInsideIsland`, см. комментарии в
  `IslandViewModel.hover`/`closeFromPointerExit`) может на пару кадров дёрнуть состояние
  hidden↔peek во время сжатия рамки — это предсуществующая особенность hover-машины, не новый баг
  от fade, не устранялось (вне скоупа задачи).

Осталось, низкий приоритет (не тронуто намеренно):
- Дублирование `formatTime`/`progressFraction`/controls между `IslandView` и `LockScreenView` —
  не баг, но правка в одном месте не подхватится в другом (уже неактуально для `IslandView`,
  см. ниже — прогресс-бар там убран).

## Форма развёрнутой карточки (2026-09-22, финал — НЕ ломать повторно)
Несколько итераций (тупиковая ветка с колонкой-календарём внутри карточки, ошибочный перегиб
в "таблетку"/pill) свелись к следующему, подтверждённому пользователем вживую решению:

- **Верхние углы — та же concave-фаска, что у collapsed pill, на ВСЕХ состояниях, включая
  expanded.** `NotchShape.topIsConvex` теперь всегда `false` — раньше expanded получал `true`
  (обычный convex-угол), из-за чего карточка читалась как отдельная плавающая коробка, а не
  как продолжение выреза экрана. `topFillet` для всех НЕ-hidden состояний = `settings.fillet`
  (13pt), единообразно. Правка в `IslandView.shape`. **Если понадобится снова трогать верх
  карточки — сначала посмотреть на collapsed pill живьём, это эталон, копировать его, а не
  изобретать заново.**
- Нижние углы — обычный squircle, `expandedBottomRadius = 36pt` на `expandedHeight = 148pt`
  (радиус явно МЕНЬШЕ половины высоты — попытка сделать радиус ~половину высоты дала "таблетку"
  вместо скруглённого прямоугольника, пользователь на это резко среагировал: **не увеличивать
  радиус относительно высоты больше этого без явного запроса**).
- `expandedWidth = 280pt`, компактно, без пустых зон: артворк 54pt, шрифты 15/12, controlsRow —
  spacing 14, иконки 13pt, play/pause круг 32pt (было 44). Верх и низ отбиты одинаковым
  `expandedTopPadding` (12pt).
- Прогресс-бар (`progressRow`) — оставлен, идёт последней строкой; без него низ карточки читался
  пустым.
- Белая обводка (`shape.stroke(...)`) вокруг острова — убрана полностью, ни в каком виде;
  пользователь явно попросил чисто чёрный без окантовки.
- **Важно для локальной отладки**: `IslandSettings` читает геометрию из `UserDefaults.standard`
  с фолбэком на `Defaults` только если ключ отсутствует. На этой машине персист несколько раз
  тихо подменял новые дефолты старыми значениями между итерациями правки (точный триггер не до
  конца продиагностирован). Практическое правило: **перед каждым визуальным тестом геометрии
  острова сначала `defaults delete com.nikita.dynamicislandmac`**, потом пересобрать/перезапустить.
- Контролы музыкальной карточки (5 иконок, круглая play/pause с белым фоном) по составу/иконкам
  не трогали.

## Фичи острова помимо Now Playing (2026-09-22)
Убрано:
- **Уведомления о зарядке/наушниках** — пользователю не понравилась анимация, убраны целиком:
  `NoticeView.swift`, `DeviceMonitors.swift`, `BluetoothDeviceInfo.swift` удалены, `IslandState.notice`
  → переиспользован как `.glance` (см. ниже), `IslandSettings.deviceNoticesEnabled` и связанный
  Toggle в `SettingsView` удалены, `AppDelegate` больше не создаёт `DeviceMonitors`.

Добавлено — обе фичи занимают тот же footprint острова (то же окно/форма), просто разный контент:
- **Таймер** (`IslandViewModel.timerRemaining`/`timerTotal`/`startTimer(minutes:)`/`cancelTimer()`) —
  запускается из меню-бара (пресеты 1/5/10/15/30 мин + «Другое…» через `NSAlert`). Пока активен,
  вытесняет Now Playing (см. `isTimerActive` в `IslandViewModel.isIslandVisible` и content-selection
  в `IslandView`): collapsed — иконка+обратный отсчёт, expanded — крупный отсчёт + прогресс-капсула
  + кнопка «Отменить». По завершении сам себя отменяет и показывает `GlanceView` "Таймер завершён".
- **Календарь — «ближайшее событие»** (`CalendarGlanceProvider.swift`, `EKEventStore`, один запрос,
  best-effort/graceful-fallback как у `LyricsProvider`) — по клику в меню-баре показывает
  `GlanceView` с названием и временем ближайшего события на 4 секунды, тем же transient-механизмом,
  что раньше был у device-уведомлений (`IslandViewModel.presentGlance`/`glanceTitle`/`glanceTimer`).
  Если событий нет — глянец "Событий больше нет". Требует `NSCalendarsFullAccessUsageDescription`
  в `build_app.sh`'s Info.plist (возвращено после того, как было убрано вместе со старой,
  отменённой веткой календаря-колонки).
- Приоритет контента при одновременной активности: `glance` (проверка календаря) > `timer` >
  Now Playing. Раньше на этом месте стоял `notice` с тем же приоритетом — просто заменили источник.

## QA через MCP `island` (2026-09-22)
Чтобы Claude мог сам гонять и проверять живое приложение.

**App-сторона** — `DebugControlServer.swift`, целиком под `#if DEBUG` (в release-бинаре его нет,
проверено `strings .build/release/DynamicIslandMac`). HTTP/JSON на `127.0.0.1:47800` через
`NWListener`, listener на main-очереди → вся работа с моделью на main thread. Лог событий только
в памяти (кольцевой буфер 300), на диск ничего. Подключение: `AppDelegate` (+ пропуск снапшотов
поллера, пока `isInjecting`), `IslandWindowController.debugIslandScreenRect` (DEBUG-extension).
Эндпоинты: `GET /state`, `GET /logs`, `POST /inject/now-playing`, `/inject/clear`,
`/simulate/hover`, `/simulate/tap`, `/simulate/glance`, `/simulate/timer`, `/simulate/lock-preview`,
`/simulate/command` (play_pause/next/previous через путь кнопок), `/inject/call`, `/inject/call/clear`,
`/simulate/call-apps`. В `/state` также `content`, `call`, `playerBundleID`, `nowPlayingSource`, `showsAppIcon`.
Координаты в `/state` — top-left, points, главный дисплей.

**MCP-сторона** — `mcp/` (Python 3.13, uv, `mcp` SDK, паттерны из `~/telegram-mcp`: Result-типы,
ничего в stdout). Инструменты: `get_state`, `inject_now_playing`, `clear_injection`, `hover`, `tap`,
`show_glance`, `start_timer`, `toggle_lock_preview`, `get_logs`, `check_invariants`,
`screenshot_island` (кроп вокруг панели через `screencapture -R`, burst до 20 кадров ≈ 80мс/кадр),
`rebuild_and_relaunch` (`./build_app.sh debug`, `pkill -x DynamicIslandMac`, `open`, ждёт `/state`).
Инварианты (`mcp/src/island_mcp/invariants.py`): `isIslandVisible == (isPlaying && title) || timer`,
`hasContent == title`, пауза/пусто без hover ⇒ `hidden`, glance ⇒ `state=glance`, окно по центру
выреза и прижато к верху, форма не шире окна, idle-ширина == ширина выреза, position ≤ duration,
индекс лирики в диапазоне.

Регистрация: `claude mcp add --scope user island -- uv --directory ~/DynamicIslandMac/mcp run island-mcp`.

Грабли:
- `rebuild_and_relaunch` пересобирает `build/DynamicIslandMac.app` в DEBUG — это та же копия, что
  обычно запущена; для обычного использования потом `./build_app.sh` (release).
- Физический вырез не попадает в скриншот: скрытый остров там выглядит как обои — это норма.
- `tap`/`hover` подменяют `pointerIsInsideIsland` на `true` (иначе watchdog через 0.1с закрывает
  карточку, т.к. реальный курсор не над островом); снимается `hover(inside=false)`.
- Никогда `pkill -f <путь к app>` — матчит и шелл, который его вызвал (убил сам себя при отладке).

## Обложка и переворот при смене трека (2026-09-23)
Найдено через MCP `island`, исправлено, проверено сериями кадров:
- **Обложка/цвет прошлого трека залипали**, если у нового трека нет обложки: `IslandViewModel.apply`
  сбрасывал `artwork` только при пустом title. Теперь при смене трека без обложки — `artwork = nil`,
  `accent = defaultAccent`. Внутри одного трека отсутствие обложки = «ещё не скачана», старая остаётся.
- **Переворот случался не всегда** (`FlipArtwork`): (1) триггер был только смена картинки — нет новой
  картинки, нет переворота; (2) `onChange(of:perform:)` видел view ДО изменения, поэтому иногда
  «переворачивал» на старую же обложку (свёрнутый остров показывал обложку прошлого трека).
  Теперь: один `onChange` на пару (trackKey, image), новые значения только из параметра; ровно один
  переворот на трек; ждём обложку до 1.2с (`coverWait`), иначе переворот на заглушку, поздняя обложка
  подставляется без второго переворота; `generation` гасит колбэки прерванного переворота при
  быстрой смене треков. В отложенных колбэках читать только `@State` (свойства view там устаревшие).
- **Неквадратная обложка вылезала за карточку** — `.frame(size)` до `.clipShape`.
- Мелочь, оставлено: пока ждём обложку (≤1.2с), эквалайзер уже бежевый (дефолтный accent), потом
  перекрашивается в цвет новой обложки.

## QA-прогон состояний через MCP (2026-09-23)
Проверено вживую: hover/peek, tap expand/collapse, пауза из карточки, fade, glance (при музыке,
поверх раскрытого таймера — после 4с возвращается в expanded), таймер (старт/отмена/финиш, без
музыки), превью лок-скрина, длинный title (обрезка «…»), пустой artist, спам 10 действий/сек,
возврат реального Spotify после `clear_injection`.

Найдено и исправлено:
- **Пауза кнопкой в раскрытой карточке убирала карточку из-под курсора** (кнопка play пропадала,
  оставалась пустая peek-таблетка). `sync()`: закреплённая кликом карточка остаётся `.expanded`,
  пока есть трек (`hasContent`), закрывается на уход курсора. `tap()` работает и по такой карточке.
  Инвариант в `mcp/.../invariants.py` обновлён: expanded на паузе допустим только под курсором.
- **Текст glance прятался под физическим вырезом**: высота была `collapsedHeight + 8`, текст по центру
  (~10–22pt от верха, x внутри выреза) — на реальном Mac закрыт камерой; на скриншотах выреза нет,
  поэтому не видно. Теперь glance растёт вниз: `collapsedHeight + glanceBodyHeight(46)`, контент с
  `padding(.top, collapsedHeight)`.
- **«Таймер завершён» показывался с иконкой календаря** — у glance теперь `symbol` (по умолчанию
  `calendar`, для таймера `timer`).
- **Позиция могла уходить за длительность** («8:20 / -0:00»): clamp в `apply` и в `positionTicker`.

Оставлено (не баги, дизайн): раскрытый таймер использует высоту музыкальной карточки — снизу ~45pt
пустоты; на лок-скрине без обложки — размытая светлая заглушка.

## Системный Now Playing и звонки (2026-09-23)
**Now Playing — любой источник.** С macOS 15.4 `MediaRemote.framework` отдаёт пустоту не-Apple
процессам (проверено на macOS 27: `MRMediaRemoteGetNowPlayingInfo` → nil). Обход — mediaremote-adapter:
`/usr/bin/perl` (Apple-signed, entitled) грузит наш маленький фреймворк и стримит состояние.
- Бандл: `Contents/Frameworks/MediaRemoteAdapter.framework` + `Contents/Resources/mediaremote-adapter.pl`
  (`build_app.sh`, universal arm64+x86_64, подписывается вместе с app через `codesign --deep`).
- `SystemNowPlaying`: `perl … stream --no-diff --debounce=100 --allow-missing-title`, каждая строка —
  полное состояние; пустой payload = ничего не играет. Перезапуск через 2с; 3 смерти без вывода →
  `onFailure` → AppleScript. `send N` — MRCommand (0 play, 1 pause, 2 toggle, 4 next, 5 prev).
- `NowPlayingPoller` раз в секунду переизлучает последнее состояние с позицией
  `elapsed + (now - timestamp)`, иначе при сворачивании позиция застывала бы.
- Хелперы → приложение (`AppIdentity.owner`): Safari играет через `com.apple.WebKit.GPU`,
  Chromium/Electron — через `<app>.helper…`. Без этого у Safari не было иконки и «Открыть».
- Страница без метаданных: title = заголовок вкладки (его даёт браузер), subtitle = имя браузера.
  Нет обложки → иконка приложения-источника (`model.displayArtwork`, `AppIcons` кэширует NSImage —
  `FlipArtwork` сравнивает по identity, новый объект на каждый рендер = вечный переворот).
- Live-стримы: адаптер выкидывает `duration=inf` → `duration 0` → в карточке и на локскрине «LIVE».
- Проверено вживую: YouTube (live, Chrome), локальная `<audio>` без метаданных (Safari),
  страница с Media Session API (Chrome), Spotify; play/pause из острова доходит до вкладки.

**Звонки** — `CallMonitor`, без API мессенджеров: CoreAudio per-process `kAudioProcessPropertyIsRunningInput`
(macOS 14.2+) + CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` для камеры. Опрос 1с на фоне.
- Звонок = известное call-приложение (список префиксов bundle id: Telegram, FaceTime/`avconferenced`,
  Zoom, Discord, WhatsApp, Slack, Teams, Skype, Viber, Signal, Webex, браузеры для Meet/веб-звонков)
  держит микрофон ≥2с; конец — через 2с после отпускания. Siri/диктовка (`com.apple.CoreSpeech`)
  держит микрофон постоянно — поэтому только белый список, не «любой, кто пишет с микрофона».
- Приоритет контента: glance > call > timer > media (`IslandViewModel.content`). Звонок делает остров
  видимым (`isIslandVisible`), но НЕ трогает `hasContent`/локскрин.
- UI: collapsed — иконка приложения, зелёная трубка, камера (если включена), таймер; expanded —
  «Звонок · App», индикаторы микрофона/камеры, кнопка «Открыть».
- Реальное обнаружение проверено через DEBUG `/simulate/call-apps` (CoreSpeech как «call-app»):
  звонок появился через 2с, ушёл через ~2с. Настоящий звонок в Telegram не делался (нельзя звонить
  людям в тестах) — UI проверен инъекцией.

Ограничения: браузер с микрофоном = «звонок» (Meet и т.п.), даже если это диктовка на сайте; mute
внутри приложения не виден (микрофон остаётся открытым); камера — глобально, не по приложению.

## Высота развёрнутой карточки — по содержимому (2026-09-23)
Заменяет фиксированную `expandedHeight` (148pt; на этой машине в UserDefaults залипло 193.6pt →
пустое поле снизу). Теперь карточки музыки, звонка и таймера меряют свою естественную высоту
(`ExpandedHeightKey` + `expandedCard(settings:)` в `IslandView`), остров обнимает её:
- содержимое прижато к верху, начинается сразу под вырезом (`notch.height + expandedTopPadding/2`),
  снизу `expandedTopPadding`; итог ≈ 155pt у музыки, ≈ 150pt у звонка/таймера;
- время в одной строке с полосой прогресса (`1:42 ━━ -2:10`), как в iOS;
- высота хранится в `IslandViewModel.expandedContentHeight`, размер считает
  `IslandViewModel.islandSize(settings:notch:)` — **общий для view и для hit-test курсора в
  `IslandWindowController`** (иначе курсор под укороченной карточкой считался бы «внутри»);
- `onPreferenceChange` висит на уровне всего острова, не на каждой карточке: заново вставленная
  карточка не сообщает начальную высоту своему наблюдателю и наследовала бы размер предыдущей;
- слайдер «Высота» развёрнутого вида убран из настроек; `expandedHeight` остаётся только размером панели.

## Зоны ответственности агентов в этом проекте
- **Planner** — приоритизация находок аудита, разбивка на фичи/фиксы.
- **Implementer** — фикс регресса в `IslandViewModel`, подключение или удаление мёртвого кода
  (`AudioOutputs`, `openPlayer`), вынос debug-логирования под флаг.
- **Tester** — у Swift-таргета нет unit-тестов; живое приложение проверяется через MCP `island`
  (`mcp/`, см. раздел «QA через MCP» выше): `check_invariants` после каждого действия + `screenshot_island`.
  Тесты самого MCP: `cd mcp && uv run pytest -q`.
- **Critic** — держит в курсе, что `hasContent` vs `isIslandVisible` разведены намеренно, не давать
  повторно смержить их без веской причины.
- **Documenter** — синхронизировать README с реальным состоянием `Sources/` (сейчас расходится).
- **Security** — приватные API (`SkyLightSpace`, AppleScript) не читают/не пишут чувствительные
  данные за пределами локального логирования — проверять при изменениях в этой области.
