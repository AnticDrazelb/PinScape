import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if case .unavailable(let reason) = model.storeHealth {
            StoreProblemView(reason: reason) {
                model.reopenStoreIfNeeded()
            }
        } else {
            app
                .modelContainer(PinStore.container)
                .id(model.storeGeneration)
        }
    }

    private var app: some View {
        @Bindable var model = model
        return HomeView()
            .fullScreenCover(item: $model.capture) { request in
                CaptureView(request: request)
            }
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .pin(let id):
                    PinDetailView(pinID: id)
                case .places:
                    PlacesView()
                case .settings:
                    SettingsView()
                case .hereNow:
                    HereNowView()
                case .sticker(let id):
                    StickerPinsView(stickerID: id)
                case .map:
                    PinMapView()
                case .captureHelp:
                    CaptureHelpSheet()
                }
            }
            .fullScreenCover(isPresented: $model.showOnboarding) {
                OnboardingView()
            }
            .alert("Not saved", isPresented: Binding(get: { model.storeAlert != nil }, set: { if !$0 { model.storeAlert = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.storeAlert ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: .pinscapeShake)) { _ in
                if PinscapeSettings.shakeToUndo {
                    model.undoLastCapture()
                }
            }
    }
}

/// Shown instead of Home when the pin store can't be opened. Pinscape never carries on with a
/// throwaway store, because a thought "saved" there would vanish when the app quit.
struct StoreProblemView: View {
    let reason: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 54, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text("Pinscape can't open your pins")
                .font(Theme.roundedTitle(.title2))
                .multilineTextAlignment(.center)
            Text("Nothing has been deleted. To make sure no thought gets lost, Pinscape won't save anything new until it can open your pins again. If this keeps happening, restart your iPhone or free up some storage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .font(.headline)
                .prominentButtonStyle()
                .padding(.top, 4)
            Text(reason)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textSelection(.enabled)
        }
        .padding(32)
    }
}
