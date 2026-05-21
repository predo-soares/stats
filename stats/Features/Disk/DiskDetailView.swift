import AppKit
import SwiftUI

struct DiskDetailView: View {
    let store: SystemStatsStore
    let onClose: () -> Void

    @State private var isScanIconSpinning = false
    @State private var selectedDiskNodeID = DiskDetailView.rootDiskNodeID
    @State private var currentFolderPage = 0

    private static let rootDiskNodeID = "\(DiskStorageNodeKind.folder.rawValue):/"
    private let folderPageSize = 12

    private var used: UInt64 { store.snapshot.diskUsed }
    private var total: UInt64 { store.snapshot.diskTotal }
    private var available: UInt64 { total > used ? total - used : 0 }
    private var scannedRoot: DiskStorageNode? { store.diskStorageScan?.root }

    private var fallbackRootNode: DiskStorageNode {
        DiskStorageNode(
            title: "Macintosh HD",
            path: "/",
            bytes: used,
            systemImage: "internaldrive",
            kind: .folder
        )
    }

    private var activeDiskNode: DiskStorageNode {
        guard let scannedRoot else { return fallbackRootNode }
        return findNode(withID: selectedDiskNodeID, in: scannedRoot) ?? scannedRoot
    }

    private var activePathNodes: [DiskStorageNode] {
        guard let scannedRoot else { return [fallbackRootNode] }
        return ancestry(for: activeDiskNode.id, in: scannedRoot) ?? [scannedRoot]
    }

    private var activeChildNodes: [DiskStorageNode] {
        activeDiskNode.children
    }

    private var pageCount: Int {
        max(Int(ceil(Double(max(activeChildNodes.count, 1)) / Double(folderPageSize))), 1)
    }

    private var pagedChildNodes: [DiskStorageNode] {
        guard !activeChildNodes.isEmpty else { return [] }
        let safePage = min(currentFolderPage, pageCount - 1)
        let startIndex = safePage * folderPageSize
        let endIndex = min(startIndex + folderPageSize, activeChildNodes.count)
        return Array(activeChildNodes[startIndex..<endIndex])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            if total > 0 {
                overview
                Divider()
                components
            } else {
                unavailableState
            }
        }
        .padding(16)
        .onAppear {
            updateScanIconAnimation(isScanning: store.isScanningDiskStorage)
            syncDiskNavigationSelection()
            Task {
                await Task.yield()
                store.refreshDiskCategoryBreakdownIfNeeded()
            }
        }
        .onChange(of: store.isScanningDiskStorage) { _, isScanning in
            updateScanIconAnimation(isScanning: isScanning)
        }
        .onChange(of: store.diskStorageScan) { _, _ in
            syncDiskNavigationSelection()
        }
        .onChange(of: store.snapshot.diskUsed) { _, _ in
            Task {
                await Task.yield()
                store.refreshDiskCategoryBreakdownIfNeeded()
            }
        }
    }

    private var header: some View {
        DetailPanelHeader(
            title: "Macintosh HD",
            subtitle: diskHeaderSubtitle,
            onClose: onClose
        ) {
            Button {
                store.scanDiskStorageNow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isScanningDiskStorage ? "arrow.triangle.2.circlepath" : "internaldrive")
                        .rotationEffect(.degrees(isScanIconSpinning ? 360 : 0))
                        .animation(
                            store.isScanningDiskStorage
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: isScanIconSpinning
                        )

                    Text(store.isScanningDiskStorage ? "Scanning" : "Scan Storage")
                }
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .font(.caption.weight(.semibold))
            .foregroundStyle(store.isScanningDiskStorage ? .secondary : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(StatsFormatting.byteString(used)) of \(StatsFormatting.byteString(total)) used")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()

                Spacer()

                if let scannedAt = store.diskCategoryBreakdown?.scannedAt {
                    Text("Categories updated \(DateFormatter.localizedString(from: scannedAt, dateStyle: .none, timeStyle: .short))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.isLoadingDiskCategoryBreakdown {
                    Text("Analyzing categories…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let diskCategoryBreakdown = store.diskCategoryBreakdown {
                DiskCategoryCapacityBar(
                    categories: diskCategoryBreakdown.categories,
                    availableBytes: available,
                    totalBytes: total
                )
                .frame(maxWidth: .infinity)
                .frame(height: 40)

                DiskCategoryLegend(
                    categories: diskCategoryBreakdown.categories,
                    availableBytes: available
                )
            } else {
                DiskCapacityBar(progress: total > 0 ? Double(used) / Double(total) : 0)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)

                HStack(alignment: .center, spacing: 14) {
                    DiskLegendItem(title: "Used", value: used, color: .primary)
                    DiskLegendItem(title: "Available", value: available, color: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.isLoadingDiskCategoryBreakdown, store.diskCategoryBreakdown != nil {
                Text("Refreshing storage categories…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 8)
    }

    private var components: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage by Folder")
                    .font(.headline.weight(.semibold))

                Spacer()

                if let scan = store.diskStorageScan {
                    Text("\(activeChildNodes.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Last scanned \(DateFormatter.localizedString(from: scan.scannedAt, dateStyle: .none, timeStyle: .short))")
                }
            }

            if store.diskStorageScan != nil {
                DiskFolderBreadcrumbs(pathNodes: activePathNodes) { node in
                    selectedDiskNodeID = node.id
                    currentFolderPage = 0
                }
            }

            if let diskStorageScan = store.diskStorageScan {
                if activeChildNodes.isEmpty {
                    Text("This folder does not contain any scanned child folders.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    DiskWindRoseView(
                        title: activeDiskNode.title,
                        nodes: pagedChildNodes,
                        totalBytes: max(activeDiskNode.bytes, 1),
                        pageLabel: pageCount > 1 ? "Page \(min(currentFolderPage + 1, pageCount)) of \(pageCount)" : nil
                    )
                    .frame(height: 300)

                    if pageCount > 1 {
                        DiskFolderPagination(
                            currentPage: min(currentFolderPage + 1, pageCount),
                            pageCount: pageCount,
                            onPrevious: {
                                currentFolderPage = max(currentFolderPage - 1, 0)
                            },
                            onNext: {
                                currentFolderPage = min(currentFolderPage + 1, pageCount - 1)
                            }
                        )
                    }

                    VStack(spacing: 8) {
                        ForEach(pagedChildNodes) { node in
                            DiskStorageListRow(node: node) {
                                guard node.isDrillDownEnabled else { return }
                                selectedDiskNodeID = node.id
                                currentFolderPage = 0
                            }
                        }
                    }
                }

                if diskStorageScan.inaccessibleItemCount > 0 {
                    Text("\(diskStorageScan.inaccessibleItemCount) items could not be read during the scan.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Run a storage scan to map folders, paginate large directories, and drill into nested usage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Disk information is unavailable")
                .font(.headline)
            Text("Refresh system stats to try reading storage capacity again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }

    private var diskHeaderSubtitle: String {
        if let scannedAt = store.diskStorageScan?.scannedAt {
            let time = DateFormatter.localizedString(from: scannedAt, dateStyle: .none, timeStyle: .short)
            return "Scanned \(time)"
        }

        return "Storage details"
    }

    private func updateScanIconAnimation(isScanning: Bool) {
        isScanIconSpinning = isScanning
    }

    private func syncDiskNavigationSelection() {
        guard let scannedRoot else {
            selectedDiskNodeID = Self.rootDiskNodeID
            currentFolderPage = 0
            return
        }

        if findNode(withID: selectedDiskNodeID, in: scannedRoot) == nil {
            selectedDiskNodeID = scannedRoot.id
        }

        currentFolderPage = min(currentFolderPage, pageCount - 1)
    }

    private func findNode(withID id: String, in node: DiskStorageNode) -> DiskStorageNode? {
        if node.id == id {
            return node
        }

        for child in node.children {
            if let match = findNode(withID: id, in: child) {
                return match
            }
        }

        return nil
    }

    private func ancestry(for id: String, in node: DiskStorageNode) -> [DiskStorageNode]? {
        if node.id == id {
            return [node]
        }

        for child in node.children {
            if let trail = ancestry(for: id, in: child) {
                return [node] + trail
            }
        }

        return nil
    }
}

private struct DiskLegendItem: View {
    let title: String
    let value: UInt64
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct DiskCategoryCapacityBar: View {
    let categories: [DiskStorageCategoryUsage]
    let availableBytes: UInt64
    let totalBytes: UInt64

    private var segments: [(id: String, color: Color, bytes: UInt64, label: String?, tooltip: String)] {
        let categorySegments = categories.map { category in
            (
                id: category.kind.rawValue,
                color: categoryColor(for: category.kind),
                bytes: category.bytes,
                label: nil as String?,
                tooltip: "\(category.kind.title): \(StatsFormatting.byteString(category.bytes))"
            )
        }

        let availableSegment = (
            id: "available",
            color: Color.white.opacity(0.16),
            bytes: availableBytes,
            label: availableBytes > 0 ? StatsFormatting.byteString(availableBytes) : nil,
            tooltip: "Available: \(StatsFormatting.byteString(availableBytes))"
        )

        return categorySegments + [availableSegment]
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(geometry.size.width, 1)

            HStack(spacing: 1) {
                ForEach(segments, id: \.id) { segment in
                    let width = segment.bytes > 0
                        ? max((Double(segment.bytes) / Double(max(totalBytes, 1))) * totalWidth, 2)
                        : 0

                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width)
                        .hoverTooltip(segment.tooltip)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DiskCategoryLegend: View {
    let categories: [DiskStorageCategoryUsage]
    let availableBytes: UInt64

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 82), spacing: 10, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(categories) { category in
                DiskLegendItem(
                    title: category.kind.title,
                    value: category.bytes,
                    color: categoryColor(for: category.kind)
                )
            }

            if availableBytes > 0 {
                DiskLegendItem(title: "Available", value: availableBytes, color: Color.white.opacity(0.28))
            }
        }
    }
}

private func categoryColor(for kind: DiskStorageCategoryKind) -> Color {
    switch kind {
    case .applications:
        return Color(red: 0.83, green: 0.40, blue: 0.29)
    case .trash:
        return Color(red: 0.89, green: 0.65, blue: 0.28)
    case .documents:
        return Color(red: 0.93, green: 0.84, blue: 0.29)
    case .photos:
        return Color(red: 0.54, green: 0.81, blue: 0.42)
    case .developer:
        return Color(red: 0.48, green: 0.80, blue: 0.76)
    case .systemData:
        return Color.white.opacity(0.56)
    }
}

private struct DiskFolderBreadcrumbs: View {
    let pathNodes: [DiskStorageNode]
    let onSelect: (DiskStorageNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(pathNodes.enumerated()), id: \.element.id) { index, node in
                    Button(action: { onSelect(node) }) {
                        Text(node.title)
                            .font(.caption.weight(index == pathNodes.count - 1 ? .semibold : .medium))
                            .foregroundStyle(index == pathNodes.count - 1 ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(index == pathNodes.count - 1 ? 0.08 : 0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if index < pathNodes.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct DiskFolderPagination: View {
    let currentPage: Int
    let pageCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(currentPage <= 1)

            Spacer()

            Text("Page \(currentPage) of \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onNext) {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(currentPage >= pageCount)
        }
        .font(.caption.weight(.semibold))
    }
}

private struct DiskWindRoseView: View {
    let title: String
    let nodes: [DiskStorageNode]
    let totalBytes: UInt64
    let pageLabel: String?

    private var maxNodeBytes: UInt64 {
        nodes.map(\.bytes).max() ?? 1
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let outerRadius = (size / 2) - 20
            let innerRadius = outerRadius * 0.22

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                Circle()
                    .inset(by: outerRadius * 0.28)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                Circle()
                    .inset(by: outerRadius * 0.56)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    let startAngle = Angle.degrees((360.0 / Double(nodes.count)) * Double(index) - 90)
                    let endAngle = Angle.degrees((360.0 / Double(nodes.count)) * Double(index + 1) - 90)
                    let fraction = max(Double(node.bytes) / Double(maxNodeBytes), 0.12)
                    let nodeOuterRadius = innerRadius + ((outerRadius - innerRadius) * fraction)

                    DiskRoseSector(startAngle: startAngle, endAngle: endAngle, innerRadius: innerRadius, outerRadius: nodeOuterRadius)
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.82 : 0.62))
                        .overlay {
                            DiskRoseSector(startAngle: startAngle, endAngle: endAngle, innerRadius: innerRadius, outerRadius: nodeOuterRadius)
                                .stroke(Color.black.opacity(0.28), lineWidth: 0.5)
                        }
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(StatsFormatting.byteString(totalBytes))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()

                    Text(pageLabel ?? "\(nodes.count) items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(16)
                .background(Color(white: 0.08).opacity(0.92), in: Circle())
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
        }
    }
}

private struct DiskRoseSector: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGFloat(startAngle.radians)
        let end = CGFloat(endAngle.radians)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addLine(to: CGPoint(
            x: center.x + cos(end) * innerRadius,
            y: center.y + sin(end) * innerRadius
        ))
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.addLine(to: CGPoint(
            x: center.x + cos(start) * outerRadius,
            y: center.y + sin(start) * outerRadius
        ))
        path.closeSubpath()
        return path
    }
}

private struct DiskStorageListRow: View {
    let node: DiskStorageNode
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: node.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(.callout.weight(.semibold))

                    Text(node.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(StatsFormatting.byteString(node.bytes))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .frame(width: 108, alignment: .trailing)

                if node.isDrillDownEnabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }
}

enum DiskAccessSupport {
    private static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    private static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")
    private static let systemSettingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    static func openFullDiskAccessSettings() {
        if let fullDiskAccessURL, NSWorkspace.shared.open(fullDiskAccessURL) {
            return
        }

        if let privacySettingsURL, NSWorkspace.shared.open(privacySettingsURL) {
            return
        }

        NSWorkspace.shared.open(systemSettingsAppURL)
    }
}
