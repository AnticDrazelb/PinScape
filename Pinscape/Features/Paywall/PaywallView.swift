import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(ProStore.self) private var store

    let reason: PaywallReason

    /// Monthly leads: £2.99 is an easier first yes than a year up front.
    @State private var plan: Plan = .monthly
    @State private var isWorking = false
    @State private var message: String?

    enum Plan {
        case monthly, yearly
    }

    private let features: [(symbol: String, title: String, detail: String)] = [
        ("infinity", "Unlimited pins", "Free keeps 10 active at once."),
        ("mappin.and.ellipse", "Unlimited places", "Home, gym, Mum's, the allotment…"),
        ("square.stack.3d.up.fill", "Place groups", "“Supermarkets” = Tesco, Aldi or Lidl."),
        ("wave.3.right.circle.fill", "NFC stickers", "Pins on the pantry door and office desk."),
        ("square.and.arrow.up.fill", "Export to Notes", "Every pin, tidy, whenever you like."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 26) {
                    header
                    featureList
                    if store.isPro {
                        Label("You're Pro. Thank you.", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .glassSurface(in: Capsule())
                    } else {
                        planPicker
                        purchaseButton
                    }
                    stickerPack
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
            }
            .glassSurface(in: Circle(), interactive: true)
            .padding(16)
            .accessibilityLabel("Close")
        }
        .preferredColorScheme(.dark)
        .alert("Pinscape Pro", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.gradient)
                    .frame(width: 92, height: 92)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 26, y: 10)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Pinscape Pro")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(reason.headline)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(features, id: \.title) { feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.gradient)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            PlanCard(
                title: "Monthly",
                price: monthlyPrice,
                detail: "Try it for a month · cancel any time",
                badge: nil,
                selected: plan == .monthly
            )
            .onTapGesture { plan = .monthly }

            PlanCard(
                title: "Yearly",
                price: yearlyPrice,
                detail: "Works out at \(monthlyEquivalent) a month",
                badge: "SAVE 30%",
                selected: plan == .yearly
            )
            .onTapGesture { plan = .yearly }
        }
        .sensoryFeedback(.selection, trigger: plan)
    }

    private var purchaseButton: some View {
        Button {
            Task { await buy(plan == .monthly ? store.monthly : store.yearly) }
        } label: {
            ZStack {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: plan)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.5), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    @ViewBuilder
    private var stickerPack: some View {
        if !store.isPro {
            Button {
                Task { await buy(store.stickerPack) }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "tag.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: "#8B5CF6").gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.hasStickerPack ? "Sticker Pack unlocked" : "Just want stickers?")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Sticker Pack for pantry and office · one-time")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Text(store.hasStickerPack ? "Owned" : (store.stickerPack?.displayPrice ?? "£9.99"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(16)
                .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.hasStickerPack || isWorking)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Restore purchases") {
                Task {
                    isWorking = true
                    await store.restore()
                    isWorking = false
                    message = store.isPro ? "Pro restored." : "No purchases found for this Apple Account."
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            Text("Subscriptions renew automatically until cancelled in Settings › Apple Account › Subscriptions. Payment is charged to your Apple Account.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    private var monthlyPrice: String { store.monthly?.displayPrice ?? "£2.99" }
    private var yearlyPrice: String { store.yearly?.displayPrice ?? "£24.99" }

    private var purchaseTitle: String {
        plan == .monthly ? "Start Pro · \(monthlyPrice) a month" : "Start Pro · \(yearlyPrice) a year"
    }

    private var monthlyEquivalent: String {
        guard let yearly = store.yearly else { return "£2.08" }
        return (yearly.price / 12).formatted(yearly.priceFormatStyle)
    }

    // MARK: Purchase

    private func buy(_ product: Product?) async {
        guard let product else {
            message = "The App Store isn't reachable right now. Try again in a moment."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await purchase(product)
            if await store.handle(result), store.isPro || store.hasStickerPack {
                dismiss()
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct PlanCard: View {
    var title: String
    var price: String
    var detail: String
    var badge: String?
    var selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.white.opacity(0.35)))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.gradient, in: Capsule())
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text(price)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(18)
        .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .animation(.snappy, value: selected)
    }
}
