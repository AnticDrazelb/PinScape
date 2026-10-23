import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HomeView()
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
                case .paywall(let reason):
                    PaywallView(reason: reason)
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
            .onReceive(NotificationCenter.default.publisher(for: .pinscapeShake)) { _ in
                if PinscapeSettings.shakeToUndo {
                    model.undoLastCapture()
                }
            }
    }
}
