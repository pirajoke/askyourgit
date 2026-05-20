import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var repoWindowController: RepoAnalysisWindowController?

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

        guard let controller = RepoAnalysisWindowController(repoURL: url) else {
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
    let updated_at: String?
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
        Mode(id: "readme", title: "README", icon: "▤"),
    ]

    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private var selectedMode = "overview"
    private var modeButtons: [String: NSButton] = [:]

    private let statusLabel = NSTextField(labelWithString: "Loading")
    private let mainTextView = NSTextView()
    private let messagesTextView = NSTextView()
    private let questionField = NSTextField()
    private let askButton = NSButton(title: "Ask", target: nil, action: nil)

    private let backgroundColor = NSColor(calibratedRed: 0.69, green: 0.69, blue: 0.68, alpha: 0.96)
    private let cardColor = NSColor(calibratedRed: 0.78, green: 0.78, blue: 0.76, alpha: 0.92)
    private let textColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    private let mutedTextColor = NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.22, alpha: 1)
    private let accentColor = NSColor(calibratedRed: 1.00, green: 0.49, blue: 0.08, alpha: 1)
    private let tealColor = NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.55, alpha: 1)

    init?(repoURL: String) {
        guard let repoRef = RepoRef(urlString: repoURL) else { return nil }
        self.repoRef = repoRef
        self.context = RepoAnalysisContext(ref: repoRef)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.minSize = NSSize(width: 560, height: 680)
        window.center()
        window.titlebarAppearsTransparent = false

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
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
        ])

        root.addArrangedSubview(makeModeBar())
        root.addArrangedSubview(makeDivider())
        root.addArrangedSubview(makeHeaderCard())

        configureTextView(mainTextView, size: 14, weight: .regular)
        mainTextView.string = "Loading GitHub repository metadata, root files, languages, and README..."
        root.addArrangedSubview(makeScrollCard(mainTextView, height: 250))

        configureTextView(messagesTextView, size: 13, weight: .regular)
        messagesTextView.string = "Ask your GIT:\nPreparing context. Ask about weak points, setup, stack, files, or what to build next.\n"
        root.addArrangedSubview(makeScrollCard(messagesTextView, height: 250))

        root.addArrangedSubview(makeInputRow())
        renderMode()
    }

    private func makeModeBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .fillEqually
        bar.spacing = 10

        for mode in modes {
            let button = NSButton(title: "\(mode.icon)\n\(mode.title)", target: self, action: #selector(selectMode(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(mode.id)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.heightAnchor.constraint(equalToConstant: 68).isActive = true
            modeButtons[mode.id] = button
            bar.addArrangedSubview(button)
        }

        updateModeButtons()
        return bar
    }

    private func makeHeaderCard() -> NSView {
        let card = makeCard()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        stack.addArrangedSubview(makeLabel("Ask your GIT", size: 26, weight: .bold, color: textColor))
        stack.addArrangedSubview(makeLabel(repoRef.fullName, size: 18, weight: .bold, color: mutedTextColor))
        stack.addArrangedSubview(makeLabel(repoRef.url, size: 12, weight: .regular, color: mutedTextColor))

        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        statusLabel.textColor = tealColor
        stack.addArrangedSubview(statusLabel)

        return card
    }

    private func makeInputRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        questionField.placeholderString = "Ask about this repo..."
        questionField.font = NSFont.systemFont(ofSize: 15)
        questionField.delegate = self
        questionField.target = self
        questionField.action = #selector(askQuestion)
        questionField.wantsLayer = true
        questionField.layer?.backgroundColor = NSColor.white.cgColor
        questionField.layer?.cornerRadius = 8
        questionField.layer?.borderWidth = 2
        questionField.layer?.borderColor = accentColor.cgColor
        questionField.heightAnchor.constraint(equalToConstant: 42).isActive = true

        askButton.target = self
        askButton.action = #selector(askQuestion)
        askButton.bezelStyle = .rounded
        askButton.keyEquivalent = "\r"
        askButton.wantsLayer = true
        askButton.layer?.backgroundColor = accentColor.cgColor
        askButton.layer?.cornerRadius = 10
        askButton.attributedTitle = NSAttributedString(
            string: "Ask",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        askButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        askButton.heightAnchor.constraint(equalToConstant: 42).isActive = true

        row.addArrangedSubview(questionField)
        row.addArrangedSubview(askButton)
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func loadContext() {
        statusLabel.stringValue = "Analyzing..."

        Task {
            do {
                let loaded = try await GitHubRepoLoader.fetch(ref: repoRef)
                await MainActor.run {
                    self.context = loaded
                    self.statusLabel.stringValue = "Ready"
                    self.renderMode()
                    self.appendAssistant("Ready. I analyzed \(loaded.ref.fullName). Ask about weak points, setup, stack, files, or next actions.")
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = "Offline context"
                    self.renderMode()
                    self.appendAssistant("I could not fetch GitHub API context. I can still answer from the repo URL, but the analysis is limited.")
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
                    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: selected ? NSColor.white : textColor,
                    .paragraphStyle: centeredParagraphStyle(),
                ]
            )
        }
    }

    private func renderMode() {
        switch selectedMode {
        case "codex":
            mainTextView.string = """
            Codex

            Use this repo with Codex when you want implementation work, bug fixes, tests, or a local agent session.

            Suggested command:
            codex "Analyze \(context.ref.url), summarize the architecture, identify weak points, and propose the first implementation step."

            Context:
            - Stack: \(context.languageSummary)
            - Root files: \(context.files.prefix(18).joined(separator: ", "))
            - README signal: \(String(context.readmeSignal.prefix(420)))
            """
        case "claude":
            mainTextView.string = """
            Claude

            Use Claude for deeper repo reasoning, long-context review, refactoring plans, and README-driven setup.

            Suggested prompt:
            Analyze \(context.ref.url). Explain the product, architecture, weak points, setup path, and the highest-impact next change.

            Signals:
            - Description: \(context.description ?? "No GitHub description.")
            - Languages: \(context.languageSummary)
            """
        case "agents":
            mainTextView.string = """
            Agent Handoff

            Good agent task:
            /goal a working improvement for \(context.ref.fullName), verified by local tests or a browser check, while preserving existing repo patterns.

            Weak points to inspect first:
            1. Setup path and missing install docs.
            2. Runtime assumptions and env vars.
            3. UI paths that depend on browser timing.
            4. Tests or smoke checks for the main workflow.
            """
        case "readme":
            mainTextView.string = """
            README Signal

            \(context.readmeSignal)
            """
        default:
            mainTextView.string = overviewText()
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

    @objc private func askQuestion() {
        let question = questionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

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
        let current = messagesTextView.string
        let separator = current.hasSuffix("\n") ? "" : "\n"
        messagesTextView.string = current + separator + "\n\(sender):\n\(text)\n"
        messagesTextView.scrollToEndOfDocument(nil)
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

    private func makeScrollCard(_ textView: NSTextView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = cardColor.cgColor
        scroll.layer?.cornerRadius = 12
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        return scroll
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
        divider.layer?.backgroundColor = NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.54, alpha: 1).cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
