import AppKit
import NookApp
import OnPaperCore
import SwiftUI

@MainActor
private final class OnPaperTrayModel: ObservableObject {
    @Published private(set) var recentAssets: [ContextAsset] = []
    @Published private(set) var statusMessage: String?

    private let store: FileBackedContextAssetStore
    private let captureService: TextClipboardCaptureService<AppKitClipboardTextReader, WorkspaceSourceAppMetadataProvider>

    init() {
        let store = FileBackedContextAssetStore(fileURL: Self.defaultAssetStoreURL())
        self.store = store
        self.captureService = TextClipboardCaptureService(
            reader: AppKitClipboardTextReader(),
            sourceProvider: WorkspaceSourceAppMetadataProvider(),
            store: store
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
                }
            } catch {
                statusMessage = "Capture failed"
            }
        }
    }

    func refreshRecentAssets() async {
        do {
            recentAssets = try await store.recent(limit: 5)
        } catch {
            recentAssets = []
            statusMessage = "Could not load recent assets"
        }
    }

    private static func defaultAssetStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("onpaper", isDirectory: true)
            .appendingPathComponent("ContextAssets.json")
    }
}

private struct OnPaperHomeView: View {
    @Environment(\.nookResolvedTheme) private var theme
    @StateObject private var model = OnPaperTrayModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            preview
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

    private var preview: some View {
        Group {
            if model.recentAssets.isEmpty {
                placeholder
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.recentAssets) { item in
                        assetRow(item)
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
