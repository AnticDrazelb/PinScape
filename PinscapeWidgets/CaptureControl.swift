import AppIntents
import SwiftUI
import WidgetKit

/// "Drop a Pin" for Control Center, the Lock Screen and the Action Button.
struct CaptureControl: ControlWidget {
    static let kind = "com.pinscape.capture-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenCaptureIntent()) {
                Label("Drop a Pin", systemImage: "mappin.and.ellipse")
            }
        }
        .displayName("Drop a Pin")
        .description("Open Pinscape listening. Say a place and a thought.")
    }
}
