import SwiftUI

/// Speak or type a thought and a place. Two seconds, then forget about it.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var model: CaptureModel
    @State private var showPicker = false
    @State private var micUnavailable = false
    @FocusState private var typing: Bool

    private let request: CaptureRequest

    init(request: CaptureRequest) {
        self.request = request
        _model = State(initialValue: CaptureModel(request: request))
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 16)

                if !typing || !model.hasContent {
                    transcript
                        .padding(.horizontal, 28)
                        .transition(.opacity)
                }

                Spacer(minLength: 16)

                if model.hasContent {
                    PreviewCard(model: model, choosePlace: { showPicker = true })
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if !typing {
                    MicOrb(level: model.speech.level, listening: model.speech.isListening) {
                        toggleListening()
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 18)
                    .transition(.scale.combined(with: .opacity))
                }

                inputBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .padding(.top, typing ? 14 : 0)
            }
            .animation(.smooth(duration: 0.35), value: model.hasContent)
            .animation(.smooth(duration: 0.3), value: typing)

            if model.stage == .saved {
                SavedOverlay(place: model.place, note: model.note)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: model.stage)
        .sensoryFeedback(.success, trigger: model.stage == .saved)
        .sensoryFeedback(.impact(weight: .light), trigger: model.speech.isListening)
        .sheet(isPresented: $showPicker) {
            PlacePickerView(note: model.note) { target in
                model.choose(target)
            }
        }
        .task {
            if request.listen && !PinStore.isDemo {
                await listen()
            } else if !PinStore.isDemo && request.text.isEmpty {
                typing = true
            }
        }
        .onChange(of: model.speech.transcript) { _, transcript in
            model.transcriptChanged(transcript)
        }
        .onChange(of: model.stage) { _, stage in
            guard stage == .saved, let pin = model.savedPin else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1_350))
                app.didCapture(pin)
                dismiss()
            }
        }
        .onChange(of: typing) { _, isTyping in
            if isTyping {
                model.speech.cancel()
                model.userInteracted()
            }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button {
                model.speech.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
            }
            .glassSurface(in: Circle(), interactive: true)
            .accessibilityLabel("Close")

            Spacer()

            Button {
                model.isAmbient.toggle()
                model.userInteracted()
            } label: {
                Label("Every visit", systemImage: "repeat")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.isAmbient ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
            }
            .glassSurface(in: Capsule(), interactive: true, tint: model.isAmbient ? Theme.rose : nil)
            .accessibilityValue(model.isAmbient ? "On" : "Off")
        }
    }

    @ViewBuilder
    private var transcript: some View {
        VStack(spacing: 14) {
            if model.speech.isListening {
                Label(model.hasContent ? "Listening" : "Listening…", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: model.speech.isListening)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            } else if micUnavailable && !model.hasContent {
                Label("Microphone is off — type instead", systemImage: "mic.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if model.hasContent {
                Text(model.text)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: model.text)
            } else {
                VStack(spacing: 10) {
                    Text("Say a place\nand a thought")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("“Tesco, batteries”  ·  “near gym, book a PT”")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $model.text, prompt: Text("Or type — “Boots, hay fever tablets”").foregroundStyle(.white.opacity(0.5)), axis: .vertical)
                .focused($typing)
                .font(.body)
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.vertical, 12)
                .padding(.leading, 18)

            Button(action: save) {
                ZStack {
                    Circle()
                        .fill(model.canSave ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    if model.isAutoSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(model.canSave ? 1 : 0.4))
                    }
                }
                .frame(width: 36, height: 36)
            }
            .disabled(!model.canSave)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .accessibilityLabel("Save pin")
        }
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: Actions

    private func toggleListening() {
        if model.speech.isListening {
            model.speech.finish()
        } else {
            Task { await listen() }
        }
    }

    private func listen() async {
        let started = await model.startListening()
        micUnavailable = !started
        if !started {
            typing = true
        }
    }

    private func save() {
        guard model.canSave else {
            if model.hasContent, model.place == nil { showPicker = true }
            return
        }
        typing = false
        if !model.save() {
            dismiss()
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                app.sheet = .paywall(.pinLimit)
            }
        }
    }
}

// MARK: - Preview card

/// Shows how Pinscape understood you: the place, and the thought.
private struct PreviewCard: View {
    let model: CaptureModel
    var choosePlace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                model.userInteracted()
                choosePlace()
            } label: {
                HStack(spacing: 12) {
                    placeGlyph
                    VStack(alignment: .leading, spacing: 2) {
                        Text(placeTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(placeSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !model.alternatives.isEmpty {
                chips(model.alternatives.map { ($0.title, $0.target) })
            } else if model.place == nil, !model.suggestions.isEmpty {
                chips(model.suggestions.map { ($0.title, $0.target) })
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: model.isAmbient ? "repeat" : "text.bubble.fill")
                    .foregroundStyle(.white.opacity(0.55))
                Text(model.note.isEmpty ? "What should it remind you?" : model.note)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(model.note.isEmpty ? .white.opacity(0.45) : .white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(.snappy, value: model.place)
    }

    @ViewBuilder
    private var placeGlyph: some View {
        if let place = model.place {
            PlaceGlyph(place, size: 42)
                .transition(.scale.combined(with: .opacity))
        } else if model.isResolving {
            ProgressView()
                .tint(.white)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.1), in: Circle())
        } else {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 42, height: 42)
                .overlay(Circle().strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        }
    }

    private var placeTitle: String {
        if let place = model.place { return place.title }
        if model.isResolving, let heard = model.heardPlace { return "Finding \(heard)…" }
        if let missing = model.missingPlace { return "Where's \(missing.displayName.lowercased())?" }
        return "Where?"
    }

    private var placeSubtitle: String {
        if let place = model.place { return place.summary }
        if model.missingPlace != nil { return "Tap to save it once" }
        return "Tap to choose a place"
    }

    private func chips(_ items: [(String, PlaceTarget)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    Button {
                        model.choose(item.1)
                    } label: {
                        PlaceChip(title: item.0, symbol: item.1.symbol, colorHex: item.1.colorHex, selected: model.place == item.1)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Orb

/// The big microphone. Its rings breathe with your voice.
struct MicOrb: View {
    var level: Double
    var listening: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(Theme.accent.opacity(ringOpacity(ring)), lineWidth: 1.5)
                        .scaleEffect(ringScale(ring))
                        .animation(.easeOut(duration: 0.18), value: level)
                }
                Circle()
                    .fill(Theme.gradient)
                    .shadow(color: Theme.accent.opacity(0.6), radius: glowRadius)
                    .scaleEffect(coreScale)
                    .animation(.easeOut(duration: 0.15), value: level)
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    .padding(3)
                Image(systemName: listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: listening ? 26 : 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 88, height: 88)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.4, bounce: 0.35), value: listening)
        .accessibilityLabel(listening ? "Stop listening" : "Speak")
    }

    private var glowRadius: CGFloat {
        listening ? CGFloat(26 + level * 20) : 16
    }

    private var coreScale: CGFloat {
        listening ? CGFloat(1 + level * 0.08) : 1
    }

    private func ringOpacity(_ ring: Int) -> Double {
        listening ? 0.45 - Double(ring) * 0.12 : 0
    }

    private func ringScale(_ ring: Int) -> CGFloat {
        guard listening else { return 0.9 }
        return CGFloat(1.12 + Double(ring) * 0.22 + level * 0.35)
    }
}

// MARK: - Saved

private struct SavedOverlay: View {
    var place: PlaceTarget?
    var note: String
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.gradient)
                        .frame(width: 110, height: 110)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 30)
                    Image(systemName: "checkmark")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: appeared)
                }
                Text("Got it.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let place {
                    HStack(spacing: 8) {
                        PlaceGlyph(place, size: 24)
                        Text(place.title)
                            .font(.headline)
                        Text("·")
                        Text(note)
                            .font(.headline.weight(.regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 32)
                }
            }
        }
        .onAppear { appeared = true }
    }
}
