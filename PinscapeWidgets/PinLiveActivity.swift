import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// While you're at a place with pins: a checklist on the Lock Screen and in the Dynamic Island.
struct PinLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PinActivityAttributes.self) { context in
            PinActivityLockScreen(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "pinscape://here"))
        } dynamicIsland: { context in
            let color = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlaceGlyph(symbol: context.attributes.symbol, colorHex: context.attributes.colorHex, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.attributes.placeName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(remainingText(context.state.remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.arrivedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(context.state.items.prefix(3)) { item in
                            PinActivityRow(item: item, tint: color)
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                PlaceGlyph(symbol: context.attributes.symbol, colorHex: context.attributes.colorHex, size: 22)
            } compactTrailing: {
                Text("\(context.state.remaining)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            } minimal: {
                PlaceGlyph(symbol: context.attributes.symbol, colorHex: context.attributes.colorHex, size: 22)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "pinscape://here"))
        }
    }
}

struct PinActivityLockScreen: View {
    let attributes: PinActivityAttributes
    let state: PinActivityAttributes.ContentState

    private var leftText: String {
        state.remaining == 0 ? "Done" : "\(state.remaining) left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlaceGlyph(symbol: attributes.symbol, colorHex: attributes.colorHex, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("YOU'RE AT")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(attributes.placeName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Text(leftText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: attributes.colorHex))
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.items.prefix(4)) { item in
                    PinActivityRow(item: item, tint: Color(hex: attributes.colorHex))
                }
            }
        }
        .padding(16)
    }
}

struct PinActivityRow: View {
    let item: PinActivityAttributes.Item
    let tint: Color

    var body: some View {
        Button(intent: CompletePinIntent(pinID: item.id)) {
            HStack(spacing: 10) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.done ? tint : .white.opacity(0.5))
                Text(item.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.done ? .white.opacity(0.45) : .white)
                    .strikethrough(item.done)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private func remainingText(_ remaining: Int) -> String {
    remaining == 0 ? "All done" : "\(remaining) to remember"
}
