import AppKit
import NookApp
import OnPaperCore
import SwiftUI

@MainActor
private final class OnPaperTrayModel: ObservableObject {
    @Published private(set) var recentAssets: [ContextAsset] = []
    @Published private(set) var statusMessage: String?
    @Published var goal = ""
    @Published var intent: PacketIntent = .debug
    @Published private(set) var selectedAssetIDs: [UUID] = []
    @Published private(set) var packetPreview: String?

    private let assetStore: FileBackedContextAssetStore
    private let captureService: TextClipboardCaptureService<AppKitClipboardTextReader, WorkspaceSourceAppMetadataProvider>
    private let composer: ContextPacketComposer

    init() {
        let assetStore = FileBackedContextAssetStore(fileURL: Self.defaultAssetStoreURL())
        let packetStore = FileBackedContextPacketStore(fileURL: Self.defaultPacketStoreURL())
        self.assetStore = assetStore
        self.captureService = TextClipboardCaptureService(
            reader: AppKitClipboardTextReader(),
            sourceProvider: WorkspaceSourceAppMetadataProvider(),
            store: assetStore
        )
        self.composer = ContextPacketComposer(
            assetStore: assetStore,
            packetStore: packetStore
        )
        Task { await refreshRecentAssets() }
    }

    func captureClipboardText() {
        Task {
            do {
                if try await captureService.captureCurrentClipboard() == nil {
                    statusMessage = "No text clipboard content"
                } else {
                    statusMessage = nil
                    await refreshRecentAssets()
                    await refreshPacketPreviewIfPossible()
                }
            } catch {
                statusMessage = "Capture failed"
            }
        }
    }

    func refreshRecentAssets() async {
        do {
            recentAssets = try await assetStore.recent(limit: 5)
            selectedAssetIDs = selectedAssetIDs.filter { id in
                recentAssets.contains { $0.id == id }
            }
        } catch {
            recentAssets = []
            selectedAssetIDs = []
            statusMessage = "Could not load recent assets"
        }
    }

    func toggleSelection(for asset: ContextAsset) {
        if let index = selectedAssetIDs.firstIndex(of: asset.id) {
            selectedAssetIDs.remove(at: index)
        } else {
            selectedAssetIDs.append(asset.id)
        }
        Task { await refreshPacketPreviewIfPossible() }
    }

    func selectionIndex(for asset: ContextAsset) -> Int? {
        selectedAssetIDs.firstIndex(of: asset.id).map { $0 + 1 }
    }

    func createPacketPreview() {
        Task { await persistAndRenderPacketPreview() }
    }

    func refreshPacketPreviewIfPossible() async {
        guard !selectedAssetIDs.isEmpty, !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            packetPreview = nil
            return
        }
        await persistAndRenderPacketPreview()
    }

    private func persistAndRenderPacketPreview() async {
        guard !selectedAssetIDs.isEmpty else {
            statusMessage = "Select at least one asset"
            packetPreview = nil
            return
        }
        guard !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "Add a goal"
            packetPreview = nil
            return
        }

        do {
            let packet = try await composer.createDraft(
                goal: goal,
                intent: intent,
                assetIDs: selectedAssetIDs
            )
            packetPreview = try await composer.render(packet).text
            statusMessage = nil
        } catch {
            packetPreview = nil
            statusMessage = "Preview failed"
        }
    }

    private static func defaultAssetStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("onpaper", isDirectory: true)
            .appendingPathComponent("ContextAssets.json")
    }

    private static func defaultPacketStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("onpaper", isDirectory: true)
            .appendingPathComponent("ContextPackets.json")
    }
}

private struct OnPaperHomeView: View {
    @Environment(\.nookResolvedTheme) private var theme
    @StateObject private var model = OnPaperTrayModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            recentAssets
            packetControls
            packetPreview
            commandRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("onpaper")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.primaryLabel)
            Text("Context packets for Codex")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
        }
    }

    private var recentAssets: some View {
        Group {
            if model.recentAssets.isEmpty {
                placeholder
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.recentAssets) { item in
                        Button {
                            model.toggleSelection(for: item)
                        } label: {
                            assetRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
            Text("No captured assets yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryLabel)
        }
    }

    private func assetRow(_ item: ContextAsset) -> some View {
        HStack(alignment: .top, spacing: 8) {
            selectionBadge(for: item)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.kind.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryLabel)
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryLabel)
                        .lineLimit(1)
                }
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionBadge(for item: ContextAsset) -> some View {
        Group {
            if let index = model.selectionIndex(for: item) {
                Text("\(index)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.blue)
                    .clipShape(Circle())
            } else {
                Circle()
                    .stroke(theme.secondaryLabel.opacity(0.5), lineWidth: 1)
                    .frame(width: 18, height: 18)
            }
        }
    }

    private var packetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Goal", text: $model.goal)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Picker("Intent", selection: $model.intent) {
                ForEach(PacketIntent.allCases, id: \.self) { intent in
                    Text(intent.rawValue.capitalized).tag(intent)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var packetPreview: some View {
        Group {
            if let preview = model.packetPreview {
                ScrollView {
                    Text(preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.primaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var commandRow: some View {
        HStack(spacing: 10) {
            Button {
                model.captureClipboardText()
            } label: {
                Label("Capture Clipboard", systemImage: "plus.square.on.square")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                model.createPacketPreview()
            } label: {
                Label("Preview Packet", systemImage: "doc.plaintext")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryLabel)
                    .lineLimit(1)
            }
        }
    }
}

private struct AppKitClipboardTextReader: ClipboardTextReading {
    func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

private struct WorkspaceSourceAppMetadataProvider: SourceAppMetadataProviding {
    func currentSourceAppMetadata() -> SourceAppMetadata? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceAppMetadata(
            name: app.localizedName,
            bundleIdentifier: app.bundleIdentifier
        )
    }
}

private struct OnPaperCompactGlyph: View, Sendable {
    var body: some View {
        Image(systemName: "doc.text")
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 24, height: 24)
    }
}

NookApp.main {
    var configuration = NookConfiguration()
    configuration.branding = NookHostBranding(
        hostName: "onpaper",
        hostTagline: "Context packets for Codex"
    )
    configuration.expandedWidth = 460
    configuration.setHome { OnPaperHomeView() }
    configuration.setCompactTrailing { OnPaperCompactGlyph() }
    configuration.onReady = { coordinator in
        let environment = ProcessInfo.processInfo.environment
        if environment["OPENNOOK_SMOKE_TEST"] != "1"
            && environment["OPENNOOK_UI_SMOKE_TEST"] != "1" {
            coordinator.showHome()
        }
    }
    return configuration
}
