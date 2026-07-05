import AppKit
import NookApp
import OnPaperCore
import SwiftUI

@MainActor
private final class OnPaperTrayModel: ObservableObject {
    @Published private var previewState = InMemoryCapturePreviewState()

    var snapshot: CapturePreviewSnapshot {
        previewState.snapshot
    }

    func captureClipboardText() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        previewState.captureText(text)
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
            if let item = model.snapshot.latestItem {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.kind.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.secondaryLabel)
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryLabel)
                            .lineLimit(1)
                    }
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryLabel)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                    Text(model.snapshot.placeholder)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var commandRow: some View {
        Button {
            model.captureClipboardText()
        } label: {
            Label("Capture Clipboard", systemImage: "plus.square.on.square")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
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
