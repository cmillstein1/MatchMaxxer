import SwiftUI

struct InstructionsView: View {
    @Bindable var model: GameModel
    var onBack: () -> Void
    var onStart: () -> Void
    @State private var showLeaderboard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            backdrop
                .ignoresSafeArea()
            // Scrim: lets the movement breathe up top while keeping the lower
            // controls fully legible.
            LinearGradient(
                colors: [.black.opacity(0.25), .black.opacity(0.55), .black.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(12)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                    Spacer()
                    Button(action: {
                        SoundPlayer.haptic(.light)
                        showLeaderboard = true
                    }) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(12)
                            .background(Circle().fill(.white.opacity(0.10)))
                    }
                }
                .padding(.bottom, 8)

                // Title
                Text(model.category.displayName.lowercased())
                    .font(.system(size: 84, weight: .black))
                    .foregroundStyle(.white)
                    .kerning(-2)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.bottom, 18)

                // Description
                VStack(alignment: .leading, spacing: 14) {
                    switch model.category {
                    case .color:
                        Text("Your eyes are liars. Most people can't reliably remember a color from one second to the next — let alone five.")
                        Text("We'll show you 5 colors, one at a time. After each one, you'll dial it back in from memory using hue, saturation, and brightness sliders.")
                    case .sound:
                        Text("Most people think they have a good ear. Some people are wrong.")
                        Text("We'll play you 5 tones, one at a time. After each one, drag your finger up and down to dial the pitch back in from memory.")
                    case .hex:
                        Text("Designers swear they know hex codes. Let's find out.")
                        Text("Ready, set, go. A hex code appears in its own color — 5 seconds on Easy, 3 on Hard. Then drag the eyedropper across the palette to find it.")
                    case .time:
                        Text("You experience time constantly. Let's see how good you are at measuring it.")
                        Text("We'll play you 5 durations — a vortex and a low hum. After each one, press and hold the screen to recreate it from memory.")
                    case .shape:
                        Text("Your spatial memory thinks it's better than it is. Let's test it.")
                        Text("A shape slides into place at some size and angle — 5 seconds on Easy, 3 on Hard. Then pinch, two-finger rotate, and drag to put it back exactly where it was.")
                    }
                }
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 32)

                Spacer(minLength: 0)

                // Players
                Text(model.mode.playerCount == 1 ? "Single Player" : "Multiplayer")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .padding(.bottom, 12)
                    .animation(.easeInOut(duration: 0.2), value: model.mode.playerCount)

                HStack(spacing: 12) {
                    playerCountButton(systemName: "person.fill", count: 1)
                    playerCountButton(systemName: "person.2.fill", count: 2)
                }
                .padding(.bottom, 28)

                // Difficulty
                Text("Difficulty")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .padding(.bottom, 12)

                DifficultyToggle(difficulty: $model.difficulty,
                                 enabledOptions: [.easy, .hard])
                    .frame(maxWidth: .infinity)

                // Start button
                Button(action: {
                    SoundPlayer.haptic(.medium)
                    onStart()
                }) {
                    HStack {
                        Text("Start")
                            .font(.system(size: 17, weight: .bold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(.white))
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .sheet(isPresented: $showLeaderboard) {
            LocalLeaderboardView(manager: LeaderboardManager.shared,
                                 category: model.category) {
                showLeaderboard = false
            }
        }
    }

    // Animated movement behind the start screen — mirrors each mode's menu card
    // so the motion carries through from home into the mode's intro.
    @ViewBuilder
    private var backdrop: some View {
        switch model.category {
        case .color:
            LinearGradient(gradient: HueGradient.stops,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.22)
        case .sound:
            WavelengthView(frequency: 320, energy: 0.9)
        case .hex:
            hexBackdrop
        case .time:
            VortexView(energy: 0.55)
        case .shape:
            ShapeShowcaseView(scale: 0.85)
        }
    }

    private var hexBackdrop: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                hexSample("#FF3B30", hue: 0)
                hexSample("#FF9500", hue: 30)
                hexSample("#FFCC00", hue: 52)
                hexSample("#34C759", hue: 135)
                hexSample("#5AC8FA", hue: 200)
                hexSample("#007AFF", hue: 220)
                hexSample("#AF52DE", hue: 280)
                hexSample("#FF2D55", hue: 340)
            }
            .padding(.trailing, 22)
        }
        .opacity(0.5)
    }

    private func hexSample(_ hex: String, hue: Double) -> some View {
        Text(hex)
            .font(.system(size: 24, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(hue: hue / 360, saturation: 0.95, brightness: 1))
    }

    @ViewBuilder
    private func playerCountButton(systemName: String, count: Int) -> some View {
        let selected = model.mode.playerCount == count
        Button {
            SoundPlayer.haptic(.light)
            model.mode = (count == 1) ? .solo : .multi(playerCount: count)
        } label: {
            ZStack {
                Circle().fill(selected ? .white : .white.opacity(0.06))
                    .overlay(Circle().stroke(.white.opacity(selected ? 0 : 0.18), lineWidth: 1))
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? .black : .white.opacity(0.85))
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selected)
    }
}
