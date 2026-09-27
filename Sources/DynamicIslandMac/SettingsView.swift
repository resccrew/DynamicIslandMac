import AppKit
import IslandGeometry
import IslandLogic
import SwiftUI

/// The settings window's tabs, in display order.
enum SettingsTab: Hashable {
    case general
    case island
    case calendar
    case lockScreen
    case advanced
}

/// Which tab is showing. Owned by the window controller so the menu can open
/// the window straight on «Календарь».
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Sizes and ranges of the settings window, in one place.
enum SettingsMetrics {
    /// One size for the window and the view inside it.
    static let windowWidth: CGFloat = 580
    static let windowHeight: CGFloat = 560

    /// Slider rows: label column, value column.
    static let labelColumn: CGFloat = 200
    static let valueColumn: CGFloat = 44
    static let exampleCommand = "island push --id build --title \"Сборка\" --progress 0.4"

    static let leadMinutes: [Double] = [1, 2, 5, 10, 15, 30]
    static let keepAwakeMinutes: [Double] = [5, 10, 15, 30, 60]

    enum Range {
        static let expandedBottomRadius = 0.0...70.0
        static let idleHeightExtra = 0.0...20.0
        static let fillet = 0.0...40.0
        static let lockScreenWidth = 240.0...600.0
        static let lockScreenArtSize = 200.0...560.0
        static let lockScreenOffsetY = -350.0...350.0
    }
}

struct SettingsView: View {
    @ObservedObject var settings: IslandSettings
    @ObservedObject var agenda: AgendaMonitor
    @ObservedObject var navigation: SettingsNavigation

    @State private var loginState = LaunchAtLogin.state
    @State private var loginError: String?
    @State private var tokenCopied = false
    @State private var exampleCopied = false
    @State private var confirmsReset = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $navigation.tab) {
                tab { general }
                    .tabItem { Label("Основное", systemImage: "gearshape") }
                    .tag(SettingsTab.general)

                tab { island }
                    .tabItem { Label("Остров", systemImage: "capsule.tophalf.filled") }
                    .tag(SettingsTab.island)

                tab { calendar }
                    .tabItem { Label("Календарь", systemImage: "calendar") }
                    .tag(SettingsTab.calendar)

                tab { lockScreen }
                    .tabItem { Label("Экран блокировки", systemImage: "lock.display") }
                    .tag(SettingsTab.lockScreen)

                tab { advanced }
                    .tabItem { Label("Дополнительно", systemImage: "slider.horizontal.3") }
                    .tag(SettingsTab.advanced)
            }
            .padding(.top, DS.Space.m)

            Divider()

            HStack {
                Button("Сбросить всё…") { confirmsReset = true }
                Spacer()
                Text("Изменения применяются сразу")
                    .font(.dsCaption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.l)
        }
        .frame(width: SettingsMetrics.windowWidth, height: SettingsMetrics.windowHeight)
        .confirmationDialog("Сбросить все настройки?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) { settings.resetToDefaults() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все настройки вернутся к значениям по умолчанию.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: permissions and login items may have changed.
            agenda.refreshAccess()
            loginState = LaunchAtLogin.state
        }
    }

    private func tab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
    }

    // MARK: - Основное

    private var general: some View {
        Group {
            Section {
                Toggle("Открывать при входе в систему", isOn: launchAtLoginBinding)
                    .disabled(loginState == .unavailable)
            } header: {
                Text("Запуск")
            } footer: {
                hint(launchAtLoginHint)
            }

            Section {
                Toggle("Значок в строке меню", isOn: $settings.showStatusIcon)
            } header: {
                Text("Строка меню")
            } footer: {
                hint("Без значка настройки открываются повторным запуском приложения.")
            }

            Section {
                Toggle("Вибрация при наведении", isOn: $settings.hoverHaptics)
            } header: {
                Text("Отклик")
            } footer: {
                hint("Лёгкий тик трекпада при касании острова. Только Force Touch.")
            }

            Section("О программе") {
                LabeledContent("Dynamic Island", value: versionText)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginState == .enabled || loginState == .requiresApproval },
            set: { enabled in
                switch LaunchAtLogin.set(enabled) {
                case .success: loginError = nil
                case .failure: loginError = "Не удалось изменить автозапуск. Проверьте «Объекты входа» в Системных настройках."
                }
                loginState = LaunchAtLogin.state
            }
        )
    }

    private var launchAtLoginHint: String {
        if let loginError { return loginError }
        switch loginState {
        case .requiresApproval: return "Разрешите приложение в «Системные настройки → Основные → Объекты входа»."
        case .unavailable: return "Работает только у установленного приложения."
        case .enabled, .disabled: return "Остров появится сам после включения Mac."
        }
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: - Остров

    private var island: some View {
        Group {
            Section("Вид") {
                presetPicker("Размер", IslandSizePreset.allCases, selected: IslandSizePreset.matching(settings),
                             title: \.title) { $0.apply(to: settings) }
                presetPicker("Реакция на наведение", HoverPreset.allCases, selected: HoverPreset.matching(settings),
                             title: \.title) { $0.apply(to: settings) }
                presetPicker("Анимация", AnimationPreset.allCases, selected: AnimationPreset.matching(settings),
                             title: \.title) { $0.apply(to: settings) }
            }

            Section {
                Picker("Экран", selection: $settings.displayPolicy) {
                    Text("Основной (со строкой меню)").tag(IslandDisplayPolicy.primary)
                    Text("Встроенный, с вырезом").tag(IslandDisplayPolicy.builtIn)
                }
            } header: {
                Text("Где показывать")
            } footer: {
                hint("Без встроенного экрана остров переезжает на основной.")
            }

            Section {
                Toggle("В полноэкранном режиме", isOn: $settings.hideInFullScreen)
                Toggle("На паузе", isOn: $settings.hideWhenPaused)
            } header: {
                Text("Когда прятать остров")
            } footer: {
                hint("На паузе остров остаётся, пока открыт источник; в полноэкранном режиме прячется.")
            }

            Section {
                Toggle("Разрешить скриптам показывать прогресс", isOn: $settings.allowExternalAPI)
                if settings.allowExternalAPI {
                    Button(exampleCopied ? "Пример скопирован" : "Скопировать пример команды") { copyExample() }
                    Button(tokenCopied ? "Токен скопирован" : "Скопировать токен") { copyToken() }
                }
            } header: {
                Text("Скрипты")
            } footer: {
                hint("Скрипты и сборки смогут показывать прогресс в острове. Доступ только с этого Mac, по токену.")
            }
        }
    }

    private func presetPicker<Preset: Identifiable & Hashable>(
        _ label: String,
        _ presets: [Preset],
        selected: Preset?,
        title: KeyPath<Preset, String>,
        apply: @escaping (Preset) -> Void
    ) -> some View {
        // Same label column as the sliders, so every control starts at one x and has one width.
        HStack(spacing: DS.Space.l) {
            Text(label)
                .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
            Picker(label, selection: Binding<Preset?>(get: { selected }, set: { $0.map(apply) })) {
                ForEach(presets) { preset in
                    Text(preset[keyPath: title]).tag(Optional(preset))
                }
                if selected == nil {
                    Text("Другой").tag(nil as Preset?)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func copyExample() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SettingsMetrics.exampleCommand, forType: .string)
        exampleCopied = true
    }

    private func copyToken() {
        guard case let .success(token) = LiveActivityToken.loadOrCreate() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        tokenCopied = true
    }

    // MARK: - Календарь

    private var calendar: some View {
        Group {
            Section {
                Toggle("Показывать события", isOn: $settings.calendarEnabled)
                if settings.calendarEnabled {
                    minutesPicker("Напоминать о событии за", $settings.eventLeadMinutes,
                                  options: SettingsMetrics.leadMinutes)
                    accessRow(agenda.eventsAccess, kind: .events)
                }
            } header: {
                Text("Календарь")
            } footer: {
                hint("Предупредит о встрече и покажет «Подключиться», если есть ссылка на созвон.")
            }

            Section {
                Toggle("Показывать напоминания", isOn: $settings.remindersEnabled)
                if settings.remindersEnabled {
                    accessRow(agenda.remindersAccess, kind: .reminders)
                }
            } header: {
                Text("Напоминания")
            } footer: {
                hint("Покажет напоминание, когда подойдёт срок, с кнопкой «Выполнено».")
            }

            Section {
                LabeledContent("Источник", value: "Системные «Календарь» и «Напоминания»")
            } header: {
                Text("Данные")
            } footer: {
                hint("Данные остаются на этом Mac. macOS спросит доступ при включении.")
            }
        }
    }

    @ViewBuilder
    private func accessRow(_ access: AgendaAccess, kind: AgendaAccessKind) -> some View {
        switch access {
        case .granted:
            Label("Доступ разрешён", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Accent.successGreen)
        case .notDetermined:
            HStack {
                Label("Нужно разрешение", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Разрешить") { agenda.requestAccess(kind) }
            }
        case .denied:
            HStack {
                Label("Нет доступа", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Accent.failureRed)
                Spacer()
                Button("Открыть Системные настройки") {
                    if let url = kind.systemSettingsURL { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    // MARK: - Экран блокировки

    private var lockScreen: some View {
        Group {
            Section {
                Toggle("Показывать на экране блокировки", isOn: $settings.lockScreenEnabled)
                Picker("Тема", selection: $settings.lockCardLightTheme) {
                    Text("Светлая").tag(true)
                    Text("Тёмная").tag(false)
                }
                .pickerStyle(.segmented)
                positionSlider
            } header: {
                Text("Карточка")
            } footer: {
                hint("Клик по обложке увеличивает её.")
            }

            Section {
                Toggle("Показывать текст песни", isOn: $settings.lyricsEnabled)
            } header: {
                Text("Тексты песен")
            } footer: {
                hint("Тексты берутся с lrclib.net: туда уходят название трека и исполнитель.")
            }

            Section {
                Toggle("Не гасить экран при блокировке", isOn: $settings.preventSleepOnLock)
                if settings.preventSleepOnLock {
                    minutesPicker("Не гасить в течение", $settings.preventSleepMinutes,
                                  options: SettingsMetrics.keepAwakeMinutes)
                }
            } header: {
                Text("Экран не гаснет")
            } footer: {
                hint("По истечении времени экран гаснет сам, чтобы беречь батарею.")
            }
        }
    }

    // MARK: - Дополнительно

    private var advanced: some View {
        Group {
            Section {
                slider("Нижний радиус", $settings.expandedBottomRadius, SettingsMetrics.Range.expandedBottomRadius)
                slider("Выступ в покое", $settings.idleHeightExtra, SettingsMetrics.Range.idleHeightExtra)
                slider("Сопряжение с экраном", $settings.fillet, SettingsMetrics.Range.fillet)
            } header: {
                Text("Остров")
            } footer: {
                hint("Тонкая настройка формы. Размер, наведение и анимация — на вкладке «Остров».")
            }

            Section {
                slider("Ширина карточки", $settings.lockScreenWidth, SettingsMetrics.Range.lockScreenWidth)
                slider("Обложка развёрнутая", $settings.lockScreenArtSize, SettingsMetrics.Range.lockScreenArtSize)
            } header: {
                Text("Экран блокировки")
            } footer: {
                hint("Размеры карточки. Положение задаётся на вкладке «Экран блокировки».")
            }

            Section {
                Toggle("Тень окна", isOn: $settings.showShadow)
            } header: {
                Text("Окно")
            } footer: {
                hint("Выключена — остров сливается с чёрной рамкой экрана.")
            }
        }
    }

    // MARK: - Building blocks

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func minutesPicker(_ label: String, _ value: Binding<Double>, options: [Double]) -> some View {
        // A value saved by an older version that isn't in the list stays selectable.
        let choices = options.contains(value.wrappedValue) ? options : (options + [value.wrappedValue]).sorted()
        return Picker(label, selection: value) {
            ForEach(choices, id: \.self) { minutes in
                Text("\(Int(minutes)) мин").tag(minutes)
            }
        }
    }

    /// The card's vertical position, said in words at the ends instead of a raw offset.
    private var positionSlider: some View {
        HStack(spacing: DS.Space.l) {
            Text("Положение по вертикали")
                .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
            Text("Выше").font(.dsCaption).foregroundStyle(.secondary)
            Slider(value: $settings.lockScreenOffsetY, in: SettingsMetrics.Range.lockScreenOffsetY)
            Text("Ниже").font(.dsCaption).foregroundStyle(.secondary)
        }
    }

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        decimals: Int = 0
    ) -> some View {
        HStack(spacing: DS.Space.l) {
            Text(label)
                .frame(width: SettingsMetrics.labelColumn, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .font(.dsCaption)
                .foregroundStyle(.secondary)
                .frame(width: SettingsMetrics.valueColumn, alignment: .trailing)
        }
    }
}
