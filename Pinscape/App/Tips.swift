import SwiftUI
import TipKit

struct ActionButtonTip: Tip {
    var title: Text { Text("Capture in two seconds") }
    var message: Text? {
        Text("Settings › Action Button › Controls › Drop a Pin. Press, speak, done. Back Tap and the Lock Screen work too.")
    }
    var image: Image? { Image(systemName: "button.horizontal.top.press.fill") }
}

struct FuzzyPlacesTip: Tip {
    var title: Text { Text("Places can be fuzzy") }
    var message: Text? {
        Text("Say “any pharmacy”, “near gym”, “downtown” or “this bench”. No addresses needed.")
    }
    var image: Image? { Image(systemName: "sparkle.magnifyingglass") }
}

struct ShakeToUndoTip: Tip {
    var title: Text { Text("Shake to undo") }
    var message: Text? { Text("Changed your mind? Give your iPhone a shake right after you drop a pin.") }
    var image: Image? { Image(systemName: "iphone.radiowaves.left.and.right") }
}
