import AppKit

/// Pages verrouillées par mot de passe (chiffrement : PageCrypto.swift).
///
/// - Verrouiller : la page est chiffrée sur le disque, puis se ferme derrière un écran de mot de passe.
/// - Déverrouiller : la clé reste en mémoire jusqu'à « Verrouiller », la mise en veille,
///   le verrouillage de la session macOS ou la fermeture de l'app. Rien n'est écrit en clair.
/// - Pas de récupération possible : mot de passe perdu = page perdue.
extension WikiStore {

    static func lockKey(_ url: URL) -> String { url.standardizedFileURL.path }

    /// La page ouverte est chiffrée et pas encore déverrouillée : on affiche l'écran de mot de passe.
    var isOpenPageLocked: Bool {
        guard openPageIsEncrypted, let openURL else { return false }
        return lockSessions[Self.lockKey(openURL)] == nil
    }

    var canLockOpenPage: Bool { openURL != nil && loadError == nil && !openPageIsEncrypted }

    func isLockedPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return lockedPages.contains(Self.lockKey(url))
    }

    /// Texte affichable d'un fichier : déchiffré si une session est ouverte, vide si la page est verrouillée.
    func readablePage(_ fileText: String, at url: URL) -> (encrypted: Bool, text: String) {
        guard PageCrypto.isLocked(fileText) else { return (false, fileText) }
        let key = Self.lockKey(url)
        if let session = lockSessions[key], let plain = try? PageCrypto.open(fileText, session: session) {
            return (true, plain)
        }
        lockSessions[key] = nil
        return (true, "")
    }

    // MARK: Verrouiller

    func requestLockPage() {
        guard canLockOpenPage else { return }
        isSetPasswordPresented = true
    }

    /// Chiffre la page ouverte avec ce mot de passe. Retourne un message d'erreur, ou nil si tout va bien.
    @MainActor
    func lockOpenPage(password: String) async -> String? {
        guard let url = openURL, canLockOpenPage else { return nil }
        save()
        let plain = rawText
        do {
            // Dérivation de la clé (≈ 0,3 s) hors du fil principal.
            let session = try await Task.detached(priority: .userInitiated) {
                try PageCrypto.newSession(password: password)
            }.value
            guard Self.lockKey(url) == openURL.map(Self.lockKey) else { return nil }
            let content = try PageCrypto.seal(plain, with: session)
            try content.write(to: url, atomically: true, encoding: .utf8)
            openPageIsEncrypted = true
            lockSessions[Self.lockKey(url)] = nil
            rawText = ""
            savedText = ""
            refreshSearchEntry(for: url, text: content)
            showToast("Page verrouillée")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Referme la page ouverte derrière son mot de passe.
    func relockOpenPage() {
        guard let url = openURL, openPageIsEncrypted else { return }
        save()
        lockSessions[Self.lockKey(url)] = nil
        rawText = ""
        savedText = ""
    }

    /// Referme toutes les pages déverrouillées (menu, veille, verrouillage de la session).
    func lockAllPages() {
        guard !lockSessions.isEmpty else { return }
        save()
        lockSessions.removeAll()
        if openPageIsEncrypted {
            rawText = ""
            savedText = ""
        }
    }

    // MARK: Déverrouiller

    /// Lève une erreur (« Mot de passe incorrect. ») si le mot de passe ne convient pas.
    @MainActor
    func unlockOpenPage(password: String) async throws {
        guard let url = openURL, isOpenPageLocked else { return }
        let fileText = try String(contentsOf: url, encoding: .utf8)
        let result = try await Task.detached(priority: .userInitiated) {
            try PageCrypto.open(fileText, password: password)
        }.value
        guard Self.lockKey(url) == openURL.map(Self.lockKey) else { return }
        lockSessions[Self.lockKey(url)] = result.session
        rawText = result.text
        savedText = result.text
    }

    /// Retire le mot de passe : la page redevient un Markdown normal (en clair).
    func removeLock() {
        guard let url = openURL, openPageIsEncrypted, !isOpenPageLocked else { return }
        save()
        do {
            try rawText.write(to: url, atomically: true, encoding: .utf8)
            openPageIsEncrypted = false
            lockSessions[Self.lockKey(url)] = nil
            savedText = rawText
            refreshSearchEntry(for: url, text: rawText)
            showToast("Mot de passe retiré")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Verrouillage automatique

    func startAutoLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            lockObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lockAllPages()
            })
        }
        lockObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.lockAllPages()
        })
    }
}
