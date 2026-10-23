import SwiftUI
import TipKit

/// The "Capture in two seconds" card. It's for people who haven't dropped a pin yet:
/// after the first one it collapses into a one-line hint on Home.
struct ActionButtonTip: Tip {
    /// Donated whenever a pin is saved.
    static let pinDropped = Tips.Event(id: "pinDropped")

    var title: Text { Text("Capture in two seconds") }
    var message: Text? {
        Text("Settings › Action Button › Controls › Drop a Pin. Press, speak, done. Back Tap and the Lock Screen work too.")
    }
    var image: Image? { Image(systemName: "button.horizontal.top.press.fill") }

    var rules: [Rule] {
        #Rule(Self.pinDropped) { $0.donations.count == 0 }
    }

    static func recordPinDropped() {
        Task { await pinDropped.donate() }
    }
}
