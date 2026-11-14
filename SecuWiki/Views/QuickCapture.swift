import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Fenêtre flottante de capture rapide (raccourci ⌃⌥N ou icône de la barre des menus).
/// Panneau « non activant » : il s'ouvre par-dessus l'app en cours sans ramener la fenêtre de Cairn.
@MainActor
final class QuickCaptureController: NSObject, NSWindowDelegate {
    static let shared = QuickCaptureController()

    private weak var store: WikiStore?
    private var panel: NSPanel?
    private var hotKey: GlobalHotKey?

    func configure(store: WikiStore) {
        self.store = store
        updateHotKey()
    }

    /// Active ou coupe le raccourci global selon le réglage.
    func updateHotKey() {
        let enabled = Prefs.bool(Prefs.quickCaptureEnabled, Prefs.Defaults.quickCaptureEnabled)
        if enabled, hotKey == nil {
            hotKey = GlobalHotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
                Task { @MainActor in self?.toggle() }
            }
        } else if !enabled {
            hotKey = nil
        }
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    func show() {
        guard let store else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Vue neuve à chaque ouverture : champ vide.
        panel.contentView = NSHostingView(rootView: QuickCaptureView { [weak self] in self?.close() }.environment(store))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        return panel
    }
}

struct QuickCaptureView: View {
    @Environment(WikiStore.self) private var store
    let onClose: () -> Void
    @State private var text = ""
    @State private var errorText: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.cairnMoss)
                Text("Capture rapide")
                    .font(.headline)
                Spacer()
                if store.rootURL != nil {
                    Text("\(store.wikiDisplayName) › Boîte de réception")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused($isFocused)
                if text.isEmpty {
                    Text("Une idée, une commande, une question pour le cours…\nLa 1re ligne devient le titre.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            } else if store.rootURL == nil {
                Text("Aucun wiki ouvert : ouvre Cairn et choisis un wiki.").font(.caption).foregroundStyle(.red)
            }

            HStack {
                Text("⌘↩ enregistrer · Échap fermer")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Annuler", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.rootURL == nil)
            }
        }
        .padding(16)
        .frame(width: 500, height: 280)
        .onAppear { isFocused = true }
    }

    private func save() {
        do {
            let title = try store.saveQuickCapture(text)
            onClose()
            store.showToast("Capturé : \(title)")
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Menu de l'icône Cairn dans la barre des menus.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture rapide…") { QuickCaptureController.shared.show() }
            .keyboardShortcut("n", modifiers: [.control, .option])
        Divider()
        Button("Ouvrir Cairn") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "main")
            }
        }
    }
}
