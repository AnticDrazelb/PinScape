import SwiftUI
import WidgetKit

@main
struct PinscapeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PinsWidget()
        CaptureWidget()
        CaptureControl()
        PinLiveActivity()
    }
}
