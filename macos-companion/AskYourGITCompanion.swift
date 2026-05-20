import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var repoWindowController: CompactRepoAnalysisWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "Ask your GIT")
            button.image?.isTemplate = true
            button.toolTip = "Ask your GIT Companion"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Ask your GIT Companion", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Install Browser Bridge", action: #selector(installBridge), key: "i"))
        menu.addItem(makeMenuItem(title: "Analyze Current Repo", action: #selector(analyzeCurrentRepo), key: "a"))
        menu.addItem(makeMenuItem(title: "Open Extension Folder", action: #selector(openExtensionFolder), key: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "Quit", action: #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.installBridgeInternal(showSuccess: false)
        }
    }

    private func makeMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func installBridge() {
        installBridgeInternal(showSuccess: true)
    }

    private func installBridgeInternal(showSuccess: Bool) {
        guard let resourcePath = Bundle.main.resourcePath else {
            show("Install failed", "Could not locate app resources.")
            return
        }

        let extensionURL: URL
        do {
            extensionURL = try installExtensionPayload()
        } catch {
            show("Install failed", "Could not prepare the Chrome extension folder.\n\n\(error.localizedDescription)")
            return
        }

        let installer = "\(resourcePath)/native-host/install.sh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [installer]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "ASKYOURGIT_EXTENSION_DIR": extensionURL.path,
        ]) { _, new in new }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if process.terminationStatus == 0 {
                if showSuccess {
                    show("Bridge installed", "Ask your GIT can now send commands to your local tools.\n\nChrome extension folder:\n\(extensionURL.path)\n\nOpen chrome://extensions, enable Developer mode, then Load unpacked and select this folder.")
                }
            } else {
                show("Install failed", output.isEmpty ? "The bridge installer exited with an error." : output)
            }
        } catch {
            show("Install failed", error.localizedDescription)
        }
    }

    @objc private func analyzeCurrentRepo() {
        let url = currentRepoURL()
        guard let url, isRepoURL(url) else {
            show("No repo detected", "Open a GitHub, GitLab, or Bitbucket repository in your browser, then choose this again.")
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        guard let controller = CompactRepoAnalysisWindowController(repoURL: url) else {
            show("No repo detected", "Could not parse the repository URL.")
            return
        }
        repoWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openExtensionFolder() {
        do {
            let extensionURL = try installExtensionPayload()
            NSWorkspace.shared.activateFileViewerSelecting([extensionURL])
        } catch {
            show("Open failed", "Could not prepare the extension folder.\n\n\(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func currentRepoURL() -> String? {
        if let activeURL = activeBrowserURL(), isRepoURL(activeURL) {
            return activeURL
        }

        return allRepoURLs().first(where: isRepoURL)
    }

    private func activeBrowserURL() -> String? {
        let script = """
        tell application "System Events"
          set frontApp to name of first application process whose frontmost is true
        end tell
        if frontApp is "Google Chrome" or frontApp is "Brave Browser" or frontApp is "Microsoft Edge" or frontApp is "Arc" then
          tell application frontApp to return URL of active tab of front window
        else if frontApp is "Safari" then
          tell application "Safari" to return URL of current tab of front window
        else
          return ""
        end if
        """

        return runAppleScript(script)
    }

    private func allRepoURLs() -> [String] {
        let script = """
        set collectedURLs to {}
        set browserApps to {"Google Chrome", "Brave Browser", "Microsoft Edge", "Safari"}

        repeat with browserApp in browserApps
          tell application "System Events"
            set isRunning to exists application process (browserApp as text)
          end tell

          if isRunning then
            try
              if (browserApp as text) is "Safari" then
                tell application "Safari"
                  repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                      set tabURL to URL of browserTab
                      if my isRepoURL(tabURL) then set end of collectedURLs to tabURL
                    end repeat
                  end repeat
                end tell
              else
                tell application (browserApp as text)
                  repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                      set tabURL to URL of browserTab
                      if my isRepoURL(tabURL) then set end of collectedURLs to tabURL
                    end repeat
                  end repeat
                end tell
              end if
            end try
          end if
        end repeat

        set AppleScript's text item delimiters to linefeed
        return collectedURLs as text

        on isRepoURL(candidateURL)
          if candidateURL starts with "https://github.com/" or candidateURL starts with "http://github.com/" or candidateURL starts with "https://gitlab.com/" or candidateURL starts with "http://gitlab.com/" or candidateURL starts with "https://bitbucket.org/" or candidateURL starts with "http://bitbucket.org/" then
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "/"
            set urlParts to text items of candidateURL
            set AppleScript's text item delimiters to oldDelimiters
            if (count of urlParts) is greater than or equal to 5 then return true
          end if
          return false
        end isRepoURL
        """

        return runAppleScript(script)?
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }

    private func revealRepoTabAndTriggerAskYourGIT(_ url: String) -> String? {
        let targetURL = appleScriptString(url)
        let launchURL = appleScriptString(companionLaunchURL(url))

        let script = """
        set targetURL to \(targetURL)
        set launchURL to \(launchURL)

        tell application "System Events"
          set chromeRunning to exists application process "Google Chrome"
          set braveRunning to exists application process "Brave Browser"
          set safariRunning to exists application process "Safari"
        end tell

        if chromeRunning then
          try
            tell application "Google Chrome"
              repeat with browserWindow in windows
                set tabIndex to 1
                repeat with browserTab in tabs of browserWindow
                  set candidateURL to URL of browserTab
                  if candidateURL starts with targetURL then
                    set active tab index of browserWindow to tabIndex
                    set index of browserWindow to 1
                    set URL of browserTab to launchURL
                    activate
                    return "triggered"
                  end if
                  set tabIndex to tabIndex + 1
                end repeat
              end repeat
            end tell
          end try
        end if

        if braveRunning then
          try
            tell application "Brave Browser"
              repeat with browserWindow in windows
                set tabIndex to 1
                repeat with browserTab in tabs of browserWindow
                  set candidateURL to URL of browserTab
                  if candidateURL starts with targetURL then
                    set active tab index of browserWindow to tabIndex
                    set index of browserWindow to 1
                    set URL of browserTab to launchURL
                    activate
                    return "triggered"
                  end if
                  set tabIndex to tabIndex + 1
                end repeat
              end repeat
            end tell
          end try
        end if

        if safariRunning then
          try
            tell application "Safari"
              repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                  set candidateURL to URL of browserTab
                  if candidateURL starts with targetURL then
                    set current tab of browserWindow to browserTab
                    set index of browserWindow to 1
                    set URL of browserTab to launchURL
                    activate
                    return "triggered"
                  end if
                end repeat
              end repeat
            end tell
          end try
        end if

        return ""
        """

        return runAppleScript(script)
    }

    private func companionLaunchURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else {
            return value + "#askyourgit=1"
        }

        let fragment = components.fragment ?? ""
        let cleanedFragment = fragment
            .replacingOccurrences(of: "askyourgit=1", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "&#?"))
        components.fragment = cleanedFragment.isEmpty
            ? "askyourgit=1"
            : "\(cleanedFragment)&askyourgit=1"
        return components.string ?? value
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func isRepoURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let host = url.host else { return false }
        let parts = url.path.split(separator: "/").filter { !$0.isEmpty }
        return parts.count >= 2 && (
            host == "github.com" ||
            host == "gitlab.com" ||
            host == "bitbucket.org"
        )
    }

    private func installedExtensionURL() -> URL {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ask your GIT", isDirectory: true)
        return supportRoot.appendingPathComponent("extension", isDirectory: true)
    }

    @discardableResult
    private func installExtensionPayload() throws -> URL {
        guard let sourceURL = Bundle.main.resourceURL?.appendingPathComponent("extension", isDirectory: true) else {
            throw NSError(domain: "AskYourGIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled extension resources are missing."])
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "AskYourGIT", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bundled extension folder was not found."])
        }

        let destinationURL = installedExtensionURL()
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func show(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

private struct RepoRef {
    let host: String
    let owner: String
    let repo: String
    let url: String

    init?(urlString: String) {
        guard let components = URLComponents(string: urlString),
              let rawHost = components.host else { return nil }

        let host = rawHost.replacingOccurrences(of: "www.", with: "")
        let parts = components.path.split(separator: "/").filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        self.host = host
        self.owner = String(parts[0])
        self.repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
        self.url = "https://\(host)/\(owner)/\(repo)"
    }

    var fullName: String {
        "\(owner)/\(repo)"
    }
}

private struct RepoAnalysisContext {
    let ref: RepoRef
    var description: String?
    var topics: [String] = []
    var primaryLanguage: String?
    var languages: [(name: String, bytes: Int)] = []
    var files: [String] = []
    var readme: String?
    var stars: Int?
    var forks: Int?
    var license: String?
    var updatedAt: String?

    var languageSummary: String {
        if languages.isEmpty {
            return primaryLanguage ?? "No language breakdown found."
        }

        let total = languages.map(\.bytes).reduce(0, +)
        guard total > 0 else {
            return languages.map(\.name).joined(separator: ", ")
        }

        return languages.prefix(5).map { item in
            let pct = Int(round((Double(item.bytes) / Double(total)) * 100))
            return "\(item.name) \(pct)%"
        }.joined(separator: ", ")
    }

    var readmeSignal: String {
        guard let readme, !readme.isEmpty else {
            return "No README text was available from the GitHub API."
        }
        return String(readme.prefix(900))
    }

    var overview: String {
        var lines: [String] = []
        lines.append("Repository: \(ref.fullName)")
        lines.append("URL: \(ref.url)")
        if let description, !description.isEmpty {
            lines.append("\nDescription:\n\(description)")
        }
        if let stars {
            lines.append("\nStars: \(stars)")
        }
        if let forks {
            lines.append("Forks: \(forks)")
        }
        if let license {
            lines.append("License: \(license)")
        }
        if let updatedAt {
            lines.append("Updated: \(updatedAt)")
        }
        lines.append("\nLanguages:\n\(languageSummary)")
        if !topics.isEmpty {
            lines.append("\nTopics:\n\(topics.prefix(12).joined(separator: ", "))")
        }
        if !files.isEmpty {
            lines.append("\nRoot files:\n\(files.prefix(30).joined(separator: ", "))")
        }
        lines.append("\nREADME signal:\n\(readmeSignal)")
        return lines.joined(separator: "\n")
    }
}

private struct GitHubRepoResponse: Decodable {
    let description: String?
    let topics: [String]?
    let language: String?
    let stargazers_count: Int?
    let forks_count: Int?
    let license: GitHubLicense?
    let updated_at: String?
}

private struct GitHubLicense: Decodable {
    let spdx_id: String?
    let name: String?
}

private struct GitHubContentItem: Decodable {
    let name: String
    let type: String
}

private struct GitHubReadmeResponse: Decodable {
    let content: String?
    let encoding: String?
}

private enum GitHubRepoLoader {
    static func fetch(ref: RepoRef) async throws -> RepoAnalysisContext {
        var context = RepoAnalysisContext(ref: ref)

        guard ref.host == "github.com" else {
            context.description = "Native app analysis currently fetches rich context for GitHub repositories. For this host, I can still use the URL and your question, but not full API metadata yet."
            return context
        }

        let base = "https://api.github.com/repos/\(ref.owner)/\(ref.repo)"

        if let repo: GitHubRepoResponse = try await requestJSON("\(base)") {
            context.description = repo.description
            context.topics = repo.topics ?? []
            context.primaryLanguage = repo.language
            context.stars = repo.stargazers_count
            context.forks = repo.forks_count
            context.license = repo.license?.spdx_id ?? repo.license?.name
            context.updatedAt = repo.updated_at
        }

        if let languages: [String: Int] = try await requestJSON("\(base)/languages") {
            context.languages = languages
                .map { (name: $0.key, bytes: $0.value) }
                .sorted { $0.bytes > $1.bytes }
        }

        if let contents: [GitHubContentItem] = try await requestJSON("\(base)/contents") {
            context.files = contents
                .sorted { lhs, rhs in
                    if lhs.type != rhs.type { return lhs.type == "dir" }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                .map { item in item.type == "dir" ? "/\(item.name)" : item.name }
        }

        if let readme: GitHubReadmeResponse = try await requestJSON("\(base)/readme"),
           let content = readme.content {
            let cleaned = content
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            if let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters),
               let text = String(data: data, encoding: .utf8) {
                context.readme = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return context
    }

    private static func requestJSON<T: Decodable>(_ urlString: String) async throws -> T? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AskYourGITCompanion/0.2", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

final class CompactRepoAnalysisWindowController: NSWindowController, NSTextFieldDelegate {
    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private var chatTranscript = ""
    private var chatStarted = false

    private let badgeStack = NSStackView()
    private let metaLabel = NSTextField(labelWithString: "Loading repo metadata...")
    private let repoLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Analyzing...")

    private let detailCard = NSView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let panelTextView = NSTextView()
    private let panelScrollView = NSScrollView()
    private let inputRow = NSStackView()
    private let questionField = NSTextField()
    private let askButton = NSButton(title: "Ask", target: nil, action: nil)

    private let backgroundColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.12, alpha: 1)
    private let cardColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)
    private let borderColor = NSColor(calibratedRed: 0.22, green: 0.25, blue: 0.31, alpha: 1)
    private let textColor = NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 1)
    private let mutedTextColor = NSColor(calibratedRed: 0.58, green: 0.62, blue: 0.70, alpha: 1)
    private let accentColor = NSColor(calibratedRed: 0.57, green: 0.36, blue: 0.98, alpha: 1)
    private let orangeColor = NSColor(calibratedRed: 1.00, green: 0.49, blue: 0.06, alpha: 1)
    private let greenColor = NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.49, alpha: 1)

    init?(repoURL: String) {
        guard let repoRef = RepoRef(urlString: repoURL) else { return nil }
        self.repoRef = repoRef
        self.context = RepoAnalysisContext(ref: repoRef)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.backgroundColor = backgroundColor
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 430, height: 570)
        window.contentMaxSize = NSSize(width: 430, height: 780)
        window.center()

        super.init(window: window)
        buildInterface()
        loadContext()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = backgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])

        root.addArrangedSubview(makeHeader())
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeActionRow(symbol: "info.circle.fill", title: "Quick Summary", action: #selector(showQuickSummary)))
        root.addArrangedSubview(makeActionRow(symbol: "bubble.left.fill", title: "Ask AI", action: #selector(showAskAI)))
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeActionRow(symbol: "diamond.fill", title: "Claude Code", action: #selector(openClaudeCode)))
        root.addArrangedSubview(makeActionRow(symbol: "play.fill", title: "Cursor", action: #selector(openCursor)))
        root.addArrangedSubview(makeActionRow(symbol: "circle.hexagongrid.fill", title: "Codex", action: #selector(openCodex)))
        root.addArrangedSubview(makeActionRow(symbol: "plus", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeActionRow(symbol: "gearshape.fill", title: "Settings", action: #selector(openSettings)))
        root.addArrangedSubview(makeActionRow(symbol: "dice.fill", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))

        configureTextView(panelTextView, size: 13, weight: .regular)
        root.addArrangedSubview(makeDetailCard())
        detailCard.isHidden = true

        root.addArrangedSubview(configureInputRow())
        inputRow.isHidden = true

        refreshBadges()
        refreshMeta()
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        badgeStack.orientation = .horizontal
        badgeStack.alignment = .leading
        badgeStack.spacing = 8
        stack.addArrangedSubview(badgeStack)

        metaLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        metaLabel.textColor = mutedTextColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(metaLabel)

        repoLabel.stringValue = repoRef.fullName
        repoLabel.font = NSFont.systemFont(ofSize: 19, weight: .bold)
        repoLabel.textColor = textColor
        repoLabel.lineBreakMode = .byTruncatingMiddle
        repoLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(repoLabel)

        urlLabel.stringValue = repoRef.url
        urlLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        urlLabel.textColor = mutedTextColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(urlLabel)

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        statusLabel.textColor = greenColor
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor),
            stack.topAnchor.constraint(equalTo: header.topAnchor),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])

        return header
    }

    private func configureInputRow() -> NSView {
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8

        questionField.placeholderString = "Ask about this repo..."
        questionField.font = NSFont.systemFont(ofSize: 15)
        questionField.textColor = textColor
        questionField.backgroundColor = cardColor
        questionField.isBezeled = false
        questionField.isBordered = false
        questionField.drawsBackground = true
        questionField.delegate = self
        questionField.target = self
        questionField.action = #selector(askQuestion)
        questionField.wantsLayer = true
        questionField.layer?.backgroundColor = cardColor.cgColor
        questionField.layer?.cornerRadius = 8
        questionField.layer?.borderWidth = 1
        questionField.layer?.borderColor = accentColor.cgColor
        questionField.focusRingType = .none
        questionField.heightAnchor.constraint(equalToConstant: 40).isActive = true

        askButton.target = self
        askButton.action = #selector(askQuestion)
        askButton.isBordered = false
        askButton.keyEquivalent = "\r"
        askButton.wantsLayer = true
        askButton.layer?.backgroundColor = orangeColor.cgColor
        askButton.layer?.cornerRadius = 9
        askButton.attributedTitle = NSAttributedString(
            string: "Ask",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        askButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        askButton.heightAnchor.constraint(equalToConstant: 40).isActive = true

        inputRow.addArrangedSubview(questionField)
        inputRow.addArrangedSubview(askButton)
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return inputRow
    }

    private func loadContext() {
        statusLabel.stringValue = "Analyzing..."

        Task {
            do {
                let loaded = try await GitHubRepoLoader.fetch(ref: repoRef)
                await MainActor.run {
                    self.context = loaded
                    self.statusLabel.stringValue = "Ready"
                    self.refreshBadges()
                    self.refreshMeta()
                    if self.chatStarted {
                        self.showAskAI()
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = "Offline context"
                    self.refreshBadges()
                    self.refreshMeta()
                }
            }
        }
    }

    @objc private func showQuickSummary() {
        showDetail(title: "Quick Summary", body: overviewText(), showsInput: false)
    }

    @objc private func showAskAI() {
        if !chatStarted {
            chatTranscript = """
            Ask your GIT:
            Ready. I analyzed \(context.ref.fullName).

            Ask about weak points, setup, stack, files, architecture, or next actions.
            """
            chatStarted = true
        }
        showDetail(title: "Ask AI", body: chatTranscript, showsInput: true)
        window?.makeFirstResponder(questionField)
    }

    @objc private func askQuestion() {
        let question = questionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        if !chatStarted {
            showAskAI()
        }

        questionField.stringValue = ""
        appendMessage("You", question)
        appendMessage("Ask your GIT", answer(for: question))
    }

    private func overviewText() -> String {
        """
        \(context.description ?? "No GitHub description available.")

        Repository:
        \(context.ref.fullName)

        Stack:
        \(context.languageSummary)

        Signals:
        Stars: \(context.stars.map { String($0) } ?? "unknown")
        Forks: \(context.forks.map { String($0) } ?? "unknown")
        License: \(context.license ?? "unknown")
        Topics: \(context.topics.isEmpty ? "none found" : context.topics.prefix(12).joined(separator: ", "))

        Root files:
        \(context.files.prefix(28).joined(separator: ", "))

        README signal:
        \(clipped(context.readmeSignal, limit: 780))
        """
    }

    private func answer(for question: String) -> String {
        let lower = question.lowercased()

        if lower.contains("weak") || lower.contains("risk") || lower.contains("problem") || lower.contains("issue") || lower.contains("bug") || lower.contains("риск") || lower.contains("проблем") {
            return """
            Weak points to inspect first:

            1. Setup reliability: can a new user run it from README only?
            2. Runtime assumptions: env vars, local services, auth, and browser permissions.
            3. Tests for the main workflow.
            4. UI timing: anything that depends on page reloads or active browser state.

            For \(context.ref.fullName), start with the stack and root files:
            \(context.languageSummary)
            \(context.files.prefix(18).joined(separator: ", "))
            """
        }

        if lower.contains("install") || lower.contains("run") || lower.contains("setup") || lower.contains("установ") || lower.contains("запуск") {
            return """
            Practical setup path:

            1. Clone \(context.ref.url)
            2. Read README first.
            3. Inspect root files: \(context.files.prefix(16).joined(separator: ", "))
            4. If package.json exists, check scripts for dev, build, and test commands.

            Stack signal:
            \(context.languageSummary)
            """
        }

        if lower.contains("file") || lower.contains("structure") || lower.contains("архит") || lower.contains("файл") || lower.contains("структ") {
            return """
            Root structure:

            \(context.files.prefix(42).joined(separator: ", "))

            I would map this into product surface, runtime/server code, shared utilities, tests, and docs before changing behavior.
            """
        }

        if lower.contains("stack") || lower.contains("language") || lower.contains("tech") || lower.contains("язык") || lower.contains("стек") {
            return """
            Detected stack:

            \(context.languageSummary)

            Primary language: \(context.primaryLanguage ?? "unknown").
            First checks should be package scripts, type checks, build output, and tests for the main runtime path.
            """
        }

        return """
        Summary:
        \(context.description ?? "No GitHub description available.")

        Key signals:
        - Languages: \(context.languageSummary)
        - Topics: \(context.topics.isEmpty ? "none found" : context.topics.prefix(10).joined(separator: ", "))
        - Root files: \(context.files.prefix(18).joined(separator: ", "))

        README signal:
        \(clipped(context.readmeSignal, limit: 560))
        """
    }

    private func appendMessage(_ sender: String, _ text: String) {
        let separator = chatTranscript.hasSuffix("\n") ? "" : "\n"
        chatTranscript = chatTranscript + separator + "\n\(sender):\n\(text)\n"
        showDetail(title: "Ask AI", body: chatTranscript, showsInput: true)
        panelTextView.scrollToEndOfDocument(nil)
    }

    @objc private func openClaudeCode() {
        sendTerminalCommand("claude \"Analyze \(context.ref.url). Summarize the repo, weak points, setup path, and first implementation step.\"")
    }

    @objc private func openCodex() {
        sendTerminalCommand("codex \"Analyze \(context.ref.url). Identify stack, risks, setup path, and next engineering action.\"")
    }

    @objc private func openCursor() {
        let repo = "\(context.ref.url).git"
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        let value = "cursor://vscode.git/clone?url=\(encodedRepo)"

        if let url = URL(string: value), NSWorkspace.shared.open(url) {
            statusLabel.stringValue = "Opening Cursor..."
        } else {
            copyToPasteboard(repo)
            showInlineNotice("Cursor URL could not be opened. I copied the clone URL instead:\n\n\(repo)")
        }
    }

    @objc private func addCustomTool() {
        showInlineNotice("Custom tool slot\n\nPrototype behavior: save a local command template here, for example:\n\nmy-tool \"Analyze \(context.ref.url)\"")
    }

    @objc private func openSettings() {
        showInlineNotice("Settings\n\nDesktop companion: Connected\nBridge: installed from the menu bar app\nRepo detection: active browser tab, then open GitHub/GitLab/Bitbucket tabs\n\nUse Install Browser Bridge from the menu to refresh native messaging.")
    }

    @objc private func shareRepo() {
        copyToPasteboard("\(context.ref.fullName) \(context.ref.url)")
        statusLabel.stringValue = "Share copied"
    }

    private func sendTerminalCommand(_ command: String) {
        copyToPasteboard(command)
        let script = """
        tell application "Terminal"
          activate
          if (count of windows) > 0 then
            do script \(appleScriptString(command)) in front window
          else
            do script \(appleScriptString(command))
          end if
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        statusLabel.stringValue = "Sent to Terminal"
    }

    private func showInlineNotice(_ text: String) {
        showDetail(title: "Ask your GIT", body: text, showsInput: false)
        statusLabel.stringValue = "Ready"
    }

    private func showDetail(title: String, body: String, showsInput: Bool) {
        resizeWindow(height: showsInput ? 760 : 720)
        detailTitleLabel.stringValue = title
        panelTextView.string = body
        detailCard.isHidden = false
        inputRow.isHidden = !showsInput
    }

    private func resizeWindow(height: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        let targetWidth: CGFloat = 430
        guard abs(frame.height - height) > 1 || abs(frame.width - targetWidth) > 1 else { return }
        let delta = height - frame.height
        frame.origin.y -= delta
        frame.size.height = height
        frame.size.width = targetWidth
        window.setFrame(frame, display: true, animate: true)
    }

    private func makeActionRow(symbol: String, title: String, badge: String? = nil, accent: Bool = false, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = backgroundColor.cgColor
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = title

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.contentTintColor = accent ? accentColor : textColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = accent ? accentColor : textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(titleLabel)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let badge {
            let badgeLabel = NSTextField(labelWithString: badge)
            badgeLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            badgeLabel.textColor = accentColor
            badgeLabel.alignment = .center
            badgeLabel.wantsLayer = true
            badgeLabel.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.07, blue: 0.28, alpha: 1).cgColor
            badgeLabel.layer?.cornerRadius = 9
            badgeLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
            stack.addArrangedSubview(badgeLabel)
        }

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 42),
            stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        return button
    }

    private func makeDetailCard() -> NSView {
        detailCard.wantsLayer = true
        detailCard.layer?.backgroundColor = cardColor.cgColor
        detailCard.layer?.borderColor = borderColor.cgColor
        detailCard.layer?.borderWidth = 1
        detailCard.layer?.cornerRadius = 12

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        detailCard.addSubview(stack)

        detailTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        detailTitleLabel.textColor = textColor
        stack.addArrangedSubview(detailTitleLabel)

        panelScrollView.translatesAutoresizingMaskIntoConstraints = false
        panelScrollView.hasVerticalScroller = true
        panelScrollView.hasHorizontalScroller = false
        panelScrollView.drawsBackground = false
        panelScrollView.borderType = .noBorder
        panelScrollView.documentView = panelTextView
        panelScrollView.heightAnchor.constraint(equalToConstant: 154).isActive = true
        panelTextView.minSize = NSSize(width: 0, height: 0)
        panelTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        stack.addArrangedSubview(panelScrollView)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: detailCard.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: -10),
        ])

        return detailCard
    }

    private func configureTextView(_ textView: NSTextView, size: CGFloat, weight: NSFont.Weight) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.font = NSFont.systemFont(ofSize: size, weight: weight)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    private func refreshBadges() {
        for view in badgeStack.arrangedSubviews {
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        var badges = context.languages.prefix(2).map { $0.name }
        if badges.isEmpty, let primary = context.primaryLanguage {
            badges = [primary]
        }
        if context.files.contains(where: { $0.lowercased().contains("docker") }) {
            badges.append("Docker")
        }
        if badges.isEmpty {
            badges = ["GitHub"]
        }

        for badge in badges.prefix(4) {
            badgeStack.addArrangedSubview(makeBadge(badge))
        }
    }

    private func refreshMeta() {
        let license = context.license ?? "LICENSE"
        let updated = formattedDate(context.updatedAt) ?? "Updated just now"
        metaLabel.stringValue = "LICENSE: \(license)   Updated: \(updated)"
    }

    private func makeBadge(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = NSColor(calibratedRed: 0.76, green: 0.58, blue: 1.0, alpha: 1)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.07, blue: 0.28, alpha: 1).cgColor
        label.layer?.cornerRadius = 14
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 78).isActive = true
        label.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return label
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedRed: 0.78, green: 0.80, blue: 0.84, alpha: 0.80).cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            return value.count >= 10 ? String(value.prefix(10)) : nil
        }

        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.dateFormat = "MMM d, yyyy"
        return display.string(from: date)
    }

    private func clipped(_ value: String, limit: Int) -> String {
        let cleaned = value.replacingOccurrences(of: "\r", with: "")
        guard cleaned.count > limit else { return cleaned }
        let prefix = cleaned.prefix(limit)
        if let lastSpace = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<lastSpace]) + "..."
        }
        return String(prefix) + "..."
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

final class RepoAnalysisWindowController: NSWindowController, NSTextFieldDelegate {
    private struct Mode {
        let id: String
        let title: String
        let icon: String
    }

    private let modes = [
        Mode(id: "overview", title: "Overview", icon: "▦"),
        Mode(id: "codex", title: "Codex", icon: "◉"),
        Mode(id: "claude", title: "Claude", icon: "✳︎"),
        Mode(id: "agents", title: "Agents", icon: "⌁"),
    ]

    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private var selectedMode = "overview"
    private var modeButtons: [String: NSButton] = [:]
    private var chatTranscript = ""
    private var chatStarted = false

    private let repoLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "Loading repo metadata...")
    private let badgeStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Analyzing...")
    private let panelTextView = NSTextView()
    private let panelScrollView = NSScrollView()
    private let inputRow = NSStackView()
    private let questionField = NSTextField()
    private let askButton = NSButton(title: "Ask", target: nil, action: nil)

    private let backgroundColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.12, alpha: 1)
    private let cardColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1)
    private let textColor = NSColor(calibratedRed: 0.89, green: 0.92, blue: 0.97, alpha: 1)
    private let mutedTextColor = NSColor(calibratedRed: 0.56, green: 0.60, blue: 0.67, alpha: 1)
    private let accentColor = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.96, alpha: 1)
    private let dividerColor = NSColor(calibratedRed: 0.72, green: 0.75, blue: 0.80, alpha: 0.70)
    private let greenColor = NSColor(calibratedRed: 0.36, green: 0.86, blue: 0.48, alpha: 1)

    init?(repoURL: String) {
        guard let repoRef = RepoRef(urlString: repoURL) else { return nil }
        self.repoRef = repoRef
        self.context = RepoAnalysisContext(ref: repoRef)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.minSize = NSSize(width: 430, height: 620)
        window.center()

        super.init(window: window)
        buildInterface()
        loadContext()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = backgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
        ])

        repoLabel.stringValue = repoRef.fullName
        repoLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        repoLabel.textColor = textColor
        repoLabel.lineBreakMode = .byTruncatingMiddle
        root.addArrangedSubview(repoLabel)

        badgeStack.orientation = .horizontal
        badgeStack.alignment = .leading
        badgeStack.spacing = 8
        root.addArrangedSubview(badgeStack)

        metaLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        metaLabel.textColor = mutedTextColor
        metaLabel.lineBreakMode = .byTruncatingTail
        root.addArrangedSubview(metaLabel)

        root.addArrangedSubview(makeModeBar())
        root.addArrangedSubview(makeDivider())

        root.addArrangedSubview(makeActionRow(icon: "ℹ", title: "Quick Summary", action: #selector(showQuickSummary)))
        root.addArrangedSubview(makeActionRow(icon: "●", title: "Ask AI", action: #selector(showAskAI)))
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeActionRow(icon: "◆", title: "Claude Code", action: #selector(openClaudeCode)))
        root.addArrangedSubview(makeActionRow(icon: "▶", title: "Cursor", action: #selector(openCursor)))
        root.addArrangedSubview(makeActionRow(icon: "◉", title: "Codex", action: #selector(openCodex)))
        root.addArrangedSubview(makeActionRow(icon: "+", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeActionRow(icon: "⚙", title: "Settings", action: #selector(openSettings)))
        root.addArrangedSubview(makeActionRow(icon: "◈", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))

        configureTextView(panelTextView, size: 13, weight: .regular)
        panelTextView.string = "Choose Quick Summary or Ask AI."
        root.addArrangedSubview(makePanelScrollView(height: 190))
        panelScrollView.isHidden = true

        root.addArrangedSubview(configureInputRow())
        inputRow.isHidden = true

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        statusLabel.textColor = greenColor
        root.addArrangedSubview(statusLabel)

        refreshBadges()
        refreshMeta()
        renderMode()
    }

    private func makeModeBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .fillEqually
        bar.spacing = 8

        for mode in modes {
            let button = NSButton(title: "\(mode.icon)\n\(mode.title)", target: self, action: #selector(selectMode(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(mode.id)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.heightAnchor.constraint(equalToConstant: 62).isActive = true
            modeButtons[mode.id] = button
            bar.addArrangedSubview(button)
        }

        updateModeButtons()
        return bar
    }

    private func configureInputRow() -> NSView {
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8

        questionField.placeholderString = "Ask about this repo..."
        questionField.font = NSFont.systemFont(ofSize: 15)
        questionField.delegate = self
        questionField.target = self
        questionField.action = #selector(askQuestion)
        questionField.wantsLayer = true
        questionField.layer?.backgroundColor = NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.95, alpha: 1).cgColor
        questionField.layer?.cornerRadius = 7
        questionField.layer?.borderWidth = 2
        questionField.layer?.borderColor = accentColor.cgColor
        questionField.heightAnchor.constraint(equalToConstant: 38).isActive = true

        askButton.target = self
        askButton.action = #selector(askQuestion)
        askButton.bezelStyle = .rounded
        askButton.keyEquivalent = "\r"
        askButton.wantsLayer = true
        askButton.layer?.backgroundColor = accentColor.cgColor
        askButton.layer?.cornerRadius = 9
        askButton.attributedTitle = NSAttributedString(
            string: "Ask",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        askButton.widthAnchor.constraint(equalToConstant: 66).isActive = true
        askButton.heightAnchor.constraint(equalToConstant: 38).isActive = true

        inputRow.addArrangedSubview(questionField)
        inputRow.addArrangedSubview(askButton)
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return inputRow
    }

    private func loadContext() {
        statusLabel.stringValue = "Analyzing..."

        Task {
            do {
                let loaded = try await GitHubRepoLoader.fetch(ref: repoRef)
                await MainActor.run {
                    self.context = loaded
                    self.statusLabel.stringValue = "Ready"
                    self.refreshBadges()
                    self.refreshMeta()
                    self.renderMode()
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = "Offline context"
                    self.refreshBadges()
                    self.refreshMeta()
                    self.renderMode()
                }
            }
        }
    }

    @objc private func selectMode(_ sender: NSButton) {
        selectedMode = sender.identifier?.rawValue ?? "overview"
        updateModeButtons()
        renderMode()
    }

    private func updateModeButtons() {
        for mode in modes {
            guard let button = modeButtons[mode.id] else { continue }
            let selected = mode.id == selectedMode
            button.layer?.backgroundColor = selected ? accentColor.cgColor : NSColor.clear.cgColor
            button.attributedTitle = NSAttributedString(
                string: "\(mode.icon)\n\(mode.title)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: selected ? NSColor.white : textColor,
                    .paragraphStyle: centeredParagraphStyle(),
                ]
            )
        }
    }

    private func renderMode() {
        switch selectedMode {
        case "codex":
            showPanel("""
            Codex

            Use this repo with Codex when you want implementation work, bug fixes, tests, or a local agent session.

            Suggested command:
            codex "Analyze \(context.ref.url), summarize the architecture, identify weak points, and propose the first implementation step."

            Context:
            - Stack: \(context.languageSummary)
            - Root files: \(context.files.prefix(18).joined(separator: ", "))
            - README signal: \(String(context.readmeSignal.prefix(420)))
            """, input: false)
        case "claude":
            showPanel("""
            Claude

            Use Claude for deeper repo reasoning, long-context review, refactoring plans, and README-driven setup.

            Suggested prompt:
            Analyze \(context.ref.url). Explain the product, architecture, weak points, setup path, and the highest-impact next change.

            Signals:
            - Description: \(context.description ?? "No GitHub description.")
            - Languages: \(context.languageSummary)
            """, input: false)
        case "agents":
            showPanel("""
            Agent Handoff

            Good agent task:
            /goal a working improvement for \(context.ref.fullName), verified by local tests or a browser check, while preserving existing repo patterns.

            Weak points to inspect first:
            1. Setup path and missing install docs.
            2. Runtime assumptions and env vars.
            3. UI paths that depend on browser timing.
            4. Tests or smoke checks for the main workflow.
            """, input: false)
        default:
            panelScrollView.isHidden = true
            inputRow.isHidden = true
        }
    }

    private func overviewText() -> String {
        """
        Overview

        \(context.description ?? "No GitHub description available.")

        Repository
        \(context.ref.fullName)

        Languages
        \(context.languageSummary)

        Topics
        \(context.topics.isEmpty ? "none found" : context.topics.prefix(12).joined(separator: ", "))

        Root files
        \(context.files.prefix(28).joined(separator: ", "))

        README signal
        \(String(context.readmeSignal.prefix(620)))
        """
    }

    @objc private func showQuickSummary() {
        showPanel(overviewText(), input: false)
    }

    @objc private func showAskAI() {
        if !chatStarted {
            chatTranscript = "Ask your GIT:\nReady. I analyzed \(context.ref.fullName). Ask about weak points, setup, stack, files, or next actions.\n"
            chatStarted = true
        }
        showPanel(chatTranscript, input: true)
        questionField.becomeFirstResponder()
    }

    @objc private func askQuestion() {
        let question = questionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        if !chatStarted {
            showAskAI()
        }
        questionField.stringValue = ""
        appendUser(question)
        appendAssistant(answer(for: question))
    }

    private func answer(for question: String) -> String {
        let lower = question.lowercased()

        if lower.contains("weak") || lower.contains("risk") || lower.contains("problem") || lower.contains("issue") || lower.contains("bug") || lower.contains("риск") || lower.contains("проблем") {
            return """
            Weak points I would inspect first:

            1. Setup reliability: can a new user run it from README only?
            2. Runtime assumptions: env vars, local services, auth, and native/browser permissions.
            3. Test coverage for the main workflow.
            4. UI timing: anything that depends on page reloads, browser state, or agent availability.

            For \(context.ref.fullName), the stack is \(context.languageSummary), so start with the TypeScript/package scripts and the README path.
            """
        }

        if lower.contains("install") || lower.contains("run") || lower.contains("setup") || lower.contains("установ") || lower.contains("запуск") {
            return """
            Practical setup path:

            1. git clone \(context.ref.url)
            2. Inspect: \(context.files.prefix(14).joined(separator: ", "))
            3. Follow README first.
            4. If package.json exists, run npm install and npm run dev/build/test depending on scripts.

            Stack signal: \(context.languageSummary)
            """
        }

        if lower.contains("file") || lower.contains("structure") || lower.contains("архит") || lower.contains("файл") || lower.contains("структ") {
            return """
            Root structure:

            \(context.files.prefix(42).joined(separator: ", "))

            I would map folders into product surface, runtime/server code, shared utilities, tests, and docs before changing behavior.
            """
        }

        if lower.contains("stack") || lower.contains("language") || lower.contains("tech") || lower.contains("язык") || lower.contains("стек") {
            return """
            Detected stack:

            \(context.languageSummary)

            Primary language: \(context.primaryLanguage ?? "unknown").
            This implies the first checks should be package scripts, type checks, build output, and tests for the main UI/runtime path.
            """
        }

        return """
        Summary:
        \(context.description ?? "No GitHub description available.")

        Key signals:
        - Languages: \(context.languageSummary)
        - Topics: \(context.topics.isEmpty ? "none found" : context.topics.prefix(10).joined(separator: ", "))
        - Root files: \(context.files.prefix(18).joined(separator: ", "))

        README signal:
        \(String(context.readmeSignal.prefix(560)))
        """
    }

    private func appendUser(_ text: String) {
        appendMessage("You", text)
    }

    private func appendAssistant(_ text: String) {
        appendMessage("Ask your GIT", text)
    }

    private func appendMessage(_ sender: String, _ text: String) {
        let current = chatTranscript
        let separator = current.hasSuffix("\n") ? "" : "\n"
        chatTranscript = current + separator + "\n\(sender):\n\(text)\n"
        showPanel(chatTranscript, input: true)
        panelTextView.scrollToEndOfDocument(nil)
    }

    @objc private func openClaudeCode() {
        sendTerminalCommand("claude \"Analyze \(context.ref.url). Summarize the repo, weak points, setup path, and first implementation step.\"")
    }

    @objc private func openCodex() {
        sendTerminalCommand("codex \"Analyze \(context.ref.url). Identify stack, risks, setup path, and next engineering action.\"")
    }

    @objc private func openCursor() {
        let value = "cursor://vscode.git/clone?url=\(context.ref.url).git"
        if let url = URL(string: value) {
            NSWorkspace.shared.open(url)
            statusLabel.stringValue = "Opening Cursor..."
        }
    }

    @objc private func addCustomTool() {
        showInlineNotice("Custom tools are in the browser extension today. Native custom tools are the next prototype step.")
    }

    @objc private func openSettings() {
        showInlineNotice("Bridge is installed. Use the menu item Install Browser Bridge to refresh native messaging.")
    }

    @objc private func shareRepo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("🎲 \(context.ref.fullName) \(context.ref.url)", forType: .string)
        statusLabel.stringValue = "Share copied"
    }

    private func sendTerminalCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let script = """
        tell application "Terminal"
          activate
          if (count of windows) > 0 then
            do script \(appleScriptString(command)) in front window
          else
            do script \(appleScriptString(command))
          end if
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        statusLabel.stringValue = "Sent to Terminal"
    }

    private func showInlineNotice(_ text: String) {
        showPanel(text, input: false)
        statusLabel.stringValue = "Ready"
    }

    private func showPanel(_ text: String, input: Bool) {
        panelTextView.string = text
        panelScrollView.isHidden = false
        inputRow.isHidden = !input
    }

    private func configureTextView(_ textView: NSTextView, size: CGFloat, weight: NSFont.Weight) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.font = NSFont.systemFont(ofSize: size, weight: weight)
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    }

    private func makePanelScrollView(height: CGFloat) -> NSScrollView {
        panelScrollView.translatesAutoresizingMaskIntoConstraints = false
        panelScrollView.hasVerticalScroller = true
        panelScrollView.hasHorizontalScroller = false
        panelScrollView.drawsBackground = false
        panelScrollView.borderType = .noBorder
        panelScrollView.documentView = panelTextView
        panelScrollView.wantsLayer = true
        panelScrollView.layer?.backgroundColor = cardColor.cgColor
        panelScrollView.layer?.cornerRadius = 12
        panelScrollView.heightAnchor.constraint(equalToConstant: height).isActive = true
        panelTextView.minSize = NSSize(width: 0, height: 0)
        panelTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return panelScrollView
    }

    private func makeCard() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = cardColor.cgColor
        view.layer?.cornerRadius = 12
        return view
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = dividerColor.cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func makeActionRow(icon: String, title: String, badge: String? = nil, accent: Bool = false, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.alignment = .left
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let text = badge == nil ? "\(icon)   \(title)" : "\(icon)   \(title)   \(badge!)"
        let color = accent ? accentColor : textColor
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: color,
            ]
        )
        return button
    }

    private func refreshBadges() {
        for view in badgeStack.arrangedSubviews {
            badgeStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        var badges = context.languages.prefix(3).map(\.name)
        if badges.isEmpty, let primary = context.primaryLanguage {
            badges = [primary]
        }
        if context.files.contains("Dockerfile") || context.files.contains("docker-compose.yml") {
            badges.append("Docker")
        }
        if badges.isEmpty {
            badges = ["GitHub"]
        }

        for badge in badges.prefix(4) {
            badgeStack.addArrangedSubview(makeBadge(badge))
        }
    }

    private func refreshMeta() {
        let license = context.license ?? "LICENSE"
        let updated = formattedDate(context.updatedAt) ?? "Updated just now"
        metaLabel.stringValue = "⚖ \(license)   ·   ⏱ \(updated)"
    }

    private func makeBadge(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = NSColor(calibratedRed: 0.76, green: 0.58, blue: 1.0, alpha: 1)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.07, blue: 0.28, alpha: 1).cgColor
        label.layer?.cornerRadius = 14
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 78).isActive = true
        label.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return label
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        return String(value.prefix(10))
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
