import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: IslandSettings

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                tab { appearance }
                    .tabItem { Label("Внешний вид", systemImage: "paintbrush") }

                tab { lockScreen }
                    .tabItem { Label("Экран блокировки", systemImage: "lock.display") }

                tab { behaviour }
                    .tabItem { Label("Поведение", systemImage: "slider.horizontal.3") }
            }
            .padding(.top, 10)

            Divider()

            HStack {
                Button("Сбросить всё") { settings.resetToDefaults() }
                Spacer()
                Text("Изменения применяются сразу")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 580)
    }

    private func tab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(20)
        }
    }

    // MARK: - Tabs

    private var appearance: some View {
        Group {
            section("Свёрнутый вид") {
                slider("Ширина", $settings.collapsedWidth, 120...700)
                slider("Высота", $settings.collapsedHeight, 20...80)
                slider("Обложка", $settings.collapsedArtwork, 10...60)
                slider("Отступ по краям", $settings.collapsedPadding, 0...60)
                slider("Нижний радиус", $settings.collapsedBottomRadius, 0...40)
            }

            section("Развёрнутый вид") {
                slider("Ширина", $settings.expandedWidth, 260...900)
                slider("Высота", $settings.expandedHeight, 120...420)
                slider("Обложка", $settings.expandedArtwork, 30...140)
                slider("Отступ по краям", $settings.expandedPadding, 0...60)
                slider("Отступ сверху", $settings.expandedTopPadding, 0...50)
                slider("Нижний радиус", $settings.expandedBottomRadius, 0...70)
            }

            section("Форма выреза") {
                slider("Выступ в покое", $settings.idleHeightExtra, 0...20)
                slider("Сопряжение с экраном", $settings.fillet, 0...40)
                slider("Кривая нижних углов", $settings.bottomExponent, 2...8, decimals: 2)
                slider("Кривая сопряжения", $settings.topExponent, 2...6, decimals: 2)
                hint("2 — обычная окружность, больше — сглаживание Apple (суперэллипс).")
            }

            section("Текст") {
                slider("Название", $settings.titleFontSize, 10...28)
                slider("Исполнитель", $settings.artistFontSize, 8...24)
            }
        }
    }

    private var lockScreen: some View {
        Group {
            section("Карточка") {
                Toggle("Показывать на экране блокировки", isOn: $settings.lockScreenEnabled)
                    .font(.system(size: 12))
                slider("Ширина карточки", $settings.lockScreenWidth, 240...600)
                slider("Обложка развёрнутая", $settings.lockScreenArtSize, 200...560)
                slider("Сдвиг по вертикали", $settings.lockScreenOffsetY, -350...350)
                Picker("Тема", selection: $settings.lockCardLightTheme) {
                    Text("Светлая").tag(true)
                    Text("Темная").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                hint("Светлая — белая непрозрачная, Темная — темная непрозрачная.")
                hint("Клик по обложке увеличивает её, затем кнопка «Текст» открывает караоке.")
            }

            section("Текст песни") {
                Toggle("Караоке", isOn: $settings.lyricsEnabled)
                    .font(.system(size: 12))
                hint("Тексты берутся с lrclib.net — туда уходят название трека и исполнитель.")
            }

            section("Питание") {
                Toggle("Не гасить экран при блокировке", isOn: $settings.preventSleepOnLock)
                    .font(.system(size: 12))
                if settings.preventSleepOnLock {
                    slider("Держать, минут", $settings.preventSleepMinutes, 1...120)
                    hint("По истечении времени экран гаснет сам, чтобы не сажать батарею.")
                }
            }
        }
    }

        private var behaviour: some View {
        Group {
            section("Наведение и анимация") {
                slider("Подрост при наведении", $settings.peekWidthGrowth, 0...80)
                slider("Подрост по высоте", $settings.peekHeightGrowth, 0...30)
                slider("Скорость анимации", $settings.animationDuration, 0.12...0.7, decimals: 2)
                hint("Наведение — лёгкий подрост с вибрацией, клик — полное раскрытие.")
            }

            section("Оформление окна") {
                Toggle("Тень окна", isOn: $settings.showShadow)
                    .font(.system(size: 12))
                hint("Выключена — остров сливается с чёрной рамкой экрана.")
            }

            section("Меню-бар") {
                Toggle("Значок в меню-баре", isOn: $settings.showStatusIcon)
                    .font(.system(size: 12))
                hint("Если выключить, настройки открываются повторным запуском приложения из «Программ».")
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func slider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        decimals: Int = 0
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 160, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
