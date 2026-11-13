// Pointer hover for charts: tracks the date under the mouse and shows a small readout at the nearest data point.
import SwiftUI
import Charts

extension View {
    /// Reports the x-axis date under the pointer (nil when the pointer leaves the plot).
    func hoverDate(_ selection: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let x = p.x - geo[proxy.plotAreaFrame].origin.x
                            selection.wrappedValue = proxy.value(atX: x, as: Date.self)
                        case .ended:
                            selection.wrappedValue = nil
                        }
                    }
            }
        }
    }
}

/// The element of `items` whose date is closest to `date`.
func nearest<T>(_ items: [T], to date: Date?, by key: (T) -> Date) -> T? {
    guard let date else { return nil }
    return items.min { abs(key($0).timeIntervalSince(date)) < abs(key($1).timeIntervalSince(date)) }
}

/// Keeps the readout inside the chart: anchor it left near the start, right near the end.
func tipAlignment<T>(_ items: [T], _ item: T, by key: (T) -> Date) -> Alignment {
    guard let first = items.map(key).min(), let last = items.map(key).max(), last > first else { return .center }
    let f = key(item).timeIntervalSince(first) / last.timeIntervalSince(first)
    return f < 0.18 ? .leading : f > 0.82 ? .trailing : .center
}

struct ChartTip: View {
    var value: String
    var detail: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.4)))
        .fixedSize()
    }
}

extension Date {
    var tipTime: String { formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
    var tipDay: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
}
