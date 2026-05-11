import SwiftUI

struct ProcessesTile: View {
    let processes: [RunningProcessStats]
    let onRefresh: () -> Void
    let onKill: (Int32) -> Void

    @State private var displayedProcesses: [RunningProcessStats] = []
    @State private var killTarget: RunningProcessStats?
    @State private var isConfirmingKill = false
    @State private var isHovered = false

    var body: some View {
        StatsTile(title: "Processes", systemImage: "list.bullet.rectangle") {
            if displayedProcesses.isEmpty {
                Text("No process CPU activity yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ProcessListHeader()

                    ForEach(Array(displayedProcesses.prefix(8).enumerated()), id: \.element.id) { index, process in
                        ProcessRow(process: process) {
                            killTarget = process
                            isConfirmingKill = true
                        }

                        if index < min(displayedProcesses.count, 8) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(12)
            .help("Refresh processes")
        }
        .confirmationDialog(
            killTarget.map { "Kill \"\($0.name)\"?" } ?? "Kill process?",
            isPresented: $isConfirmingKill,
            titleVisibility: .visible
        ) {
            Button("Kill Process", role: .destructive) {
                guard let killTarget else { return }
                displayedProcesses.removeAll { $0.pid == killTarget.pid }
                onKill(killTarget.pid)
                self.killTarget = nil
            }
            Button("Cancel", role: .cancel) {
                killTarget = nil
            }
        } message: {
            if let killTarget {
                Text("PID \(killTarget.pid) · usage \(cpuString(killTarget.cpuPercent))")
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                displayedProcesses = processes
            }
        }
        .onAppear {
            displayedProcesses = processes
        }
        .onChange(of: processes) { _, newValue in
            if !isHovered {
                displayedProcesses = newValue
            }
        }
    }

    private func cpuString(_ value: Double) -> String {
        StatsFormatting.processPercentString(value)
    }
}

private struct ProcessListHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("PID")
                .frame(width: 52, alignment: .trailing)

            Text("Usage")
                .frame(width: 54, alignment: .trailing)

            Color.clear
                .frame(width: 22, height: 1)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }
}

private struct ProcessRow: View {
    let process: RunningProcessStats
    let onKillRequest: () -> Void

    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(process.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(process.pid)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

            Text(cpuString)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)

            Button(action: onKillRequest) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isRowHovered ? .red : .secondary)
            .help("Kill process")
        }
        .font(.caption)
        .padding(.vertical, 4)
        .background(isRowHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
    }

    private var cpuString: String {
        StatsFormatting.processPercentString(process.cpuPercent)
    }
}
