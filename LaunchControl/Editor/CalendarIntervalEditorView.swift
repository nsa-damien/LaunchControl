import SwiftUI

struct CalendarIntervalEditorView: View {
    @Binding var intervals: [CalendarInterval]
    let isEditable: Bool

    private static let weekdayNames = [
        1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday",
        5: "Friday", 6: "Saturday", 7: "Sunday"
    ]

    var body: some View {
        Section("Calendar Schedule") {
            ForEach(intervals.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    Picker("Day", selection: Binding(
                        get: { intervals[index].weekday ?? 0 },
                        set: { intervals[index].weekday = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Any").tag(0)
                        ForEach(1...7, id: \.self) { day in
                            Text(Self.weekdayNames[day] ?? "").tag(day)
                        }
                    }
                    .frame(maxWidth: 140)
                    .disabled(!isEditable)

                    Picker("Hour", selection: Binding(
                        get: { intervals[index].hour ?? 0 },
                        set: { intervals[index].hour = $0 }
                    )) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h)).tag(h)
                        }
                    }
                    .frame(maxWidth: 70)
                    .disabled(!isEditable)

                    Text(":")

                    Picker("Min", selection: Binding(
                        get: { intervals[index].minute ?? 0 },
                        set: { intervals[index].minute = $0 }
                    )) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m)).tag(m)
                        }
                    }
                    .frame(maxWidth: 70)
                    .disabled(!isEditable)

                    if isEditable {
                        Button(action: { intervals.remove(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if isEditable {
                Button(action: {
                    intervals.append(CalendarInterval(hour: 0, minute: 0))
                }) {
                    Label("Add Schedule", systemImage: "plus.circle")
                }
            }
            if intervals.isEmpty {
                Text("No schedule")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
