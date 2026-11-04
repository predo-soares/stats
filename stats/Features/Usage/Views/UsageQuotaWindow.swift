import SwiftUI

struct UsageQuotaWindow: View {
    let name: String
    let remainingFraction: Double
    let resetsAt: Date?

    private var percent: Int { Int((remainingFraction * 100).rounded()) }
    private var fill: Color { remainingFraction <= 0.2 ? .red : .accentColor }
    private var clampedFraction: Double { min(max(remainingFraction, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule()
                        .fill(fill)
                        .frame(width: geometry.size.width * clampedFraction)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(percent)% left").font(.subheadline).monospacedDigit()
                Spacer()
                if let resetsAt {
                    Text("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
