import SwiftUI

struct UsagePeriodPicker: View {
    @Binding var selection: UsageComparisonPeriod
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(UsageComparisonPeriod.allCases.count)
            let slotWidth = proxy.size.width / count
            let index = CGFloat(UsageComparisonPeriod.allCases.firstIndex(of: selection) ?? 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: max(0, slotWidth - 6), height: max(0, proxy.size.height - 6))
                    .offset(x: index * slotWidth + 3)
                    .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82), value: selection)
                HStack(spacing: 0) {
                    ForEach(UsageComparisonPeriod.allCases) { period in
                        Button {
                            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)) {
                                selection = period
                            }
                        } label: {
                            Text(period.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == period ? Color.primary : Color.secondary)
                        .accessibilityAddTraits(selection == period ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: 32)
    }
}
