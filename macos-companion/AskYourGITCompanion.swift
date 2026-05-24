import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var repoWindowController: WebRepoAnalysisWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = statusBarIcon()
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

    private func statusBarIcon() -> NSImage? {
        let resourcePath = Bundle.main.resourcePath ?? ""
        let candidates = [
            "\(resourcePath)/extension/icons/icon128.png",
            "\(resourcePath)/AppIcon.icns",
        ]

        for path in candidates {
            if let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 24, height: 24)
                image.isTemplate = false
                return image
            }
        }

        let fallback = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted", accessibilityDescription: "Ask your GIT")
        fallback?.isTemplate = true
        return fallback
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

        guard let controller = WebRepoAnalysisWindowController(repoURL: url) else {
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

private final class CompactActionRow: NSControl {
    private let normalColor: NSColor
    private let hoverColor: NSColor

    init(symbol: String, title: String, badge: String? = nil, accent: Bool = false, target: AnyObject?, action: Selector?) {
        self.normalColor = NSColor.clear
        self.hoverColor = NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1)
        super.init(frame: .zero)

        self.target = target
        self.action = action
        wantsLayer = true
        layer?.backgroundColor = normalColor.cgColor
        layer?.cornerRadius = 8

        let textColor = accent
            ? NSColor(calibratedRed: 0.57, green: 0.36, blue: 0.98, alpha: 1)
            : NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 1)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.contentTintColor = textColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(iconView)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = textColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        stack.addArrangedSubview(label)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        if let badge {
            let badgeLabel = NSTextField(labelWithString: badge)
            badgeLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            badgeLabel.textColor = NSColor(calibratedRed: 0.76, green: 0.58, blue: 1.0, alpha: 1)
            badgeLabel.alignment = .center
            badgeLabel.wantsLayer = true
            badgeLabel.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.07, blue: 0.28, alpha: 1).cgColor
            badgeLabel.layer?.cornerRadius = 9
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeLabel.heightAnchor.constraint(equalToConstant: 20).isActive = true
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
            stack.addArrangedSubview(badgeLabel)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}

final class WebRepoAnalysisWindowController: NSWindowController, WKScriptMessageHandler {
    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private let webView: WKWebView
    private var isLoadingContext = false
    private var loadError: String?
    private var pendingQuestions: [String] = []

    init?(repoURL: String) {
        guard let repoRef = RepoRef(urlString: repoURL) else { return nil }
        self.repoRef = repoRef
        self.context = RepoAnalysisContext(ref: repoRef)

        let userContent = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContent
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 432, height: 688),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        window.contentMinSize = NSSize(width: 432, height: 688)
        window.contentMaxSize = NSSize(width: 432, height: 688)
        window.center()

        super.init(window: window)
        userContent.add(self, name: "askyourgit")
        buildInterface()
        loadContext(renderLoadingPage: true)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "askyourgit")
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = nil
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func loadContext(renderLoadingPage: Bool = false) {
        guard !isLoadingContext else { return }
        isLoadingContext = true
        loadError = nil
        if renderLoadingPage {
            renderPage()
        }

        Task {
            do {
                let loaded = try await GitHubRepoLoader.fetch(ref: repoRef)
                await MainActor.run {
                    self.context = loaded
                    self.isLoadingContext = false
                    if !self.hasRepoContext, self.repoRef.host == "github.com" {
                        self.loadError = "GitHub API returned no repository details."
                    }
                    self.finishContextLoad()
                }
            } catch {
                await MainActor.run {
                    self.isLoadingContext = false
                    self.loadError = error.localizedDescription
                    self.finishContextLoad()
                }
            }
        }
    }

    private func finishContextLoad() {
        let questions = pendingQuestions
        pendingQuestions.removeAll()

        if questions.isEmpty {
            renderPage()
            return
        }

        evaluate("setStatus(\(jsString(loadError == nil ? "Ready" : "Context limited")));")
        for question in questions {
            evaluate("appendMessage('assistant', \(jsString(answer(for: question))));")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "summary":
            evaluate("showDetail('Quick Summary', \(jsString(overviewText())));")
        case "ask-mode":
            evaluate("showChat(\(jsString(initialChatText())));")
        case "ask":
            let question = (body["question"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty else { return }
            if shouldWaitForContextBeforeAnswering {
                pendingQuestions.append(question)
                evaluate("setStatus('Loading GitHub');")
                evaluate("appendMessage('assistant', \(jsString("Loading repository context from GitHub first. I will answer with README, languages, topics, and files in a moment.")));")
                loadContext()
                return
            }
            evaluate("appendMessage('assistant', \(jsString(answer(for: question))));")
        case "claude":
            sendTerminalCommand("claude \"Analyze \(context.ref.url). Summarize the repo, weak points, setup path, and first implementation step.\"")
            evaluate("setStatus('Sent to Claude Code');")
        case "codex":
            sendTerminalCommand("codex \"Analyze \(context.ref.url). Identify stack, risks, setup path, and next engineering action.\"")
            evaluate("setStatus('Sent to Codex');")
        case "cursor":
            openCursor()
            evaluate("setStatus('Opening Cursor');")
        case "copy-url":
            copyToPasteboard(context.ref.url)
            evaluate("setStatus('Repo URL copied');")
        case "share":
            copyToPasteboard("\(context.ref.fullName) \(context.ref.url)")
            evaluate("setStatus('Share text copied');")
        case "settings":
            evaluate("showDetail('Settings', \(jsString(settingsText())));")
        case "custom":
            evaluate("showDetail('Custom Tool', \(jsString("Prototype slot for a saved local command template. Next step: persist a command like my-tool \"Analyze {url}\" and expose it here.")));")
        default:
            break
        }
    }

    private func renderPage() {
        webView.loadHTMLString(makeHTML(), baseURL: nil)
    }

    private func makeHTML() -> String {
        let badges = currentBadges().map { "<span class=\"chip\">\(html($0))</span>" }.joined()
        let topicBadges = context.topics.prefix(3).map { "<span class=\"mini-chip\">\(html($0))</span>" }.joined()
        let topics = topicBadges.isEmpty ? "<span class=\"empty-chip\">\(isLoadingContext ? "Loading topics" : "No topics")</span>" : topicBadges
        let description = html(context.description ?? (isLoadingContext ? "Loading GitHub description..." : "No GitHub description available."))
        let updated = html(formattedDate(context.updatedAt) ?? "Updated just now")
        let license = html(context.license ?? "LICENSE")
        let readmeSignal = html(isLoadingContext ? "Loading README signal..." : clipped(context.readmeSignal, limit: 320))
        let files = html(context.files.prefix(10).joined(separator: " · "))
        let stack = html(isLoadingContext ? "Loading language breakdown..." : context.languageSummary)
        let stars = html(context.stars.map(String.init) ?? "0")
        let forks = html(context.forks.map(String.init) ?? "0")
        let statusText = html(isLoadingContext ? "Loading GitHub" : (loadError == nil ? "Ready" : "Context limited"))
        let primary = html(context.primaryLanguage ?? (isLoadingContext ? "Loading" : "Repo"))

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: dark;
              --bg: #0d111a;
              --panel: #121824;
              --panel-2: #192131;
              --panel-3: #20293a;
              --line: rgba(219, 230, 255, .16);
              --text: #eef4ff;
              --muted: #9aa6ba;
              --orange: #ff870f;
              --orange-2: #ff6815;
              --purple: #9b68ff;
              --purple-2: #24153e;
              --cyan: #17c1cc;
              --green: #5df28b;
            }
            * { box-sizing: border-box; }
            html, body { width: 100%; min-height: 100%; }
            body {
              margin: 0;
              background: linear-gradient(180deg, #121824 0%, #0d111a 100%);
              color: var(--text);
              font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
              letter-spacing: 0;
              overflow: hidden;
            }
            button, input { font-family: inherit; }
            .shell {
              height: 100vh;
              display: flex;
              flex-direction: column;
              padding: 14px 14px 12px;
            }
            .tabs {
              display: grid;
              grid-template-columns: repeat(5, minmax(0, 1fr));
              gap: 7px;
              padding: 0 0 12px;
              border-bottom: 1px solid var(--line);
              flex: 0 0 auto;
            }
            .tab {
              height: 58px;
              border: 1px solid transparent;
              border-radius: 13px;
              background: transparent;
              color: var(--muted);
              font-weight: 800;
              display: flex;
              flex-direction: column;
              align-items: center;
              justify-content: center;
              gap: 4px;
              padding: 0 4px;
              cursor: pointer;
              user-select: none;
            }
            .tab .glyph { font-size: 19px; line-height: 1; }
            .tab .label {
              max-width: 100%;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
              font-size: 12px;
            }
            .tab.active {
              color: white;
              background: linear-gradient(180deg, var(--orange), var(--orange-2));
              box-shadow: 0 12px 26px rgba(255, 120, 12, .26);
            }
            .content {
              flex: 1 1 auto;
              min-height: 0;
              overflow: auto;
              padding: 13px 0 10px;
              scrollbar-width: thin;
            }
            .hero {
              border: 1px solid var(--line);
              border-radius: 18px;
              background:
                linear-gradient(135deg, rgba(255,255,255,.075), rgba(255,255,255,.025)),
                var(--panel);
              padding: 14px;
              box-shadow: inset 0 1px 0 rgba(255,255,255,.08);
            }
            .chip-row {
              display: flex;
              flex-wrap: wrap;
              gap: 7px;
              margin-bottom: 11px;
            }
            .chip, .mini-chip, .empty-chip, .count-chip {
              display: inline-flex;
              align-items: center;
              min-height: 24px;
              padding: 4px 10px;
              border-radius: 999px;
              font-weight: 800;
              color: #d8c7ff;
              background: var(--purple-2);
            }
            .mini-chip, .empty-chip {
              color: #b9c4d8;
              background: rgba(255,255,255,.06);
              font-weight: 700;
            }
            .empty-chip { color: #7f8aa0; }
            .count-chip {
              min-width: 56px;
              justify-content: center;
              color: #ffdfc0;
              background: rgba(255, 135, 15, .15);
            }
            .meta {
              display: flex;
              flex-wrap: wrap;
              gap: 7px 12px;
              color: var(--muted);
              font-size: 12px;
              font-weight: 800;
              margin: 0 0 10px;
            }
            .repo {
              margin: 0 0 6px;
              font-size: 22px;
              line-height: 1.08;
              font-weight: 850;
              overflow-wrap: anywhere;
            }
            .url {
              color: #a9b5c8;
              font-size: 12px;
              font-weight: 700;
              overflow-wrap: anywhere;
            }
            .status {
              display: inline-flex;
              gap: 7px;
              align-items: center;
              color: var(--green);
              font-weight: 850;
              margin: 10px 0 0;
            }
            .quick {
              display: grid;
              grid-template-columns: repeat(3, minmax(0, 1fr));
              gap: 8px;
              margin: 12px 0 0;
            }
            .metric {
              min-height: 54px;
              padding: 10px;
              border-radius: 14px;
              border: 1px solid var(--line);
              background: rgba(255,255,255,.045);
              overflow: hidden;
            }
            .metric b {
              display: block;
              color: var(--text);
              font-size: 14px;
              margin-bottom: 3px;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
            .metric span {
              color: var(--muted);
              font-size: 11px;
              font-weight: 750;
            }
            .panel {
              margin-top: 12px;
              border: 1px solid var(--line);
              border-radius: 18px;
              background: rgba(18, 24, 36, .72);
              overflow: hidden;
            }
            .section-title {
              margin: 0;
              padding: 10px 13px 7px;
              color: #8490a5;
              text-transform: uppercase;
              font-size: 10px;
              letter-spacing: .09em;
              font-weight: 850;
            }
            .row {
              width: 100%;
              display: flex;
              align-items: center;
              gap: 11px;
              min-height: 46px;
              padding: 9px 13px;
              border: 0;
              border-top: 1px solid rgba(219,230,255,.08);
              border-radius: 0;
              background: transparent;
              color: var(--text);
              text-align: left;
              font-size: 16px;
              font-weight: 800;
              cursor: pointer;
            }
            .row:hover { background: rgba(255,255,255,.055); }
            .row .icon {
              width: 25px;
              height: 25px;
              display: grid;
              place-items: center;
              color: #e7eefc;
              flex: 0 0 25px;
              font-size: 18px;
            }
            .row .title {
              min-width: 0;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
            .row.accent { color: #a879ff; }
            .row small {
              margin-left: auto;
              flex: 0 0 auto;
              padding: 3px 8px;
              border-radius: 999px;
              background: rgba(154,108,255,.22);
              color: #d6c4ff;
              font-size: 11px;
              font-weight: 850;
            }
            .signal-card {
              margin: 12px 0 0;
              border: 1px solid var(--line);
              border-radius: 16px;
              background: rgba(255,255,255,.035);
              padding: 12px;
            }
            .signal-card h3 {
              margin: 0 0 6px;
              font-size: 15px;
            }
            .signal-card p {
              margin: 0;
              color: #cbd5e6;
              font-size: 12px;
              line-height: 1.45;
            }
            .detail, .chat {
              margin-top: 12px;
              border: 1px solid var(--line);
              border-radius: 18px;
              background: var(--panel);
              overflow: hidden;
            }
            .detail h3, .chat h3 {
              margin: 0;
              padding: 12px 13px;
              border-bottom: 1px solid var(--line);
              font-size: 14px;
            }
            .detail pre {
              margin: 0;
              max-height: 210px;
              padding: 13px;
              overflow: auto;
              white-space: pre-wrap;
              color: #dce6f7;
              font: 12px/1.48 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            }
            .chat-log {
              display: flex;
              flex-direction: column;
              gap: 8px;
              min-height: 126px;
              max-height: 210px;
              overflow: auto;
              padding: 11px;
            }
            .msg {
              max-width: 86%;
              padding: 9px 11px;
              border-radius: 13px;
              white-space: pre-wrap;
              line-height: 1.42;
              font-size: 12px;
            }
            .assistant { align-self: flex-start; background: #1b2230; border: 1px solid var(--line); }
            .user { align-self: flex-end; background: linear-gradient(135deg, #8d5cff, #6938ef); }
            .askbar {
              display: flex;
              gap: 8px;
              padding: 9px;
              border-top: 1px solid var(--line);
            }
            input {
              flex: 1;
              min-width: 0;
              height: 38px;
              border: 1px solid rgba(154,108,255,.45);
              border-radius: 11px;
              outline: none;
              padding: 0 11px;
              background: #0d121b;
              color: var(--text);
              font-size: 13px;
            }
            .send {
              flex: 0 0 58px;
              border: 0;
              border-radius: 11px;
              background: var(--orange);
              color: white;
              font-weight: 850;
              cursor: pointer;
            }
            .hidden { display: none; }
          </style>
        </head>
        <body>
          <div class="shell">
            <div class="tabs">
              <button class="tab active" data-tab="overview"><span class="glyph">▦</span><span class="label">Overview</span></button>
              <button class="tab" data-tab="codex"><span class="glyph">✽</span><span class="label">Codex</span></button>
              <button class="tab" data-tab="claude"><span class="glyph">✦</span><span class="label">Claude</span></button>
              <button class="tab" data-tab="cursor"><span class="glyph">▶</span><span class="label">Cursor</span></button>
              <button class="tab" data-tab="tools"><span class="glyph">↔</span><span class="label">Tools</span></button>
            </div>

            <main class="content">
              <section class="hero">
                <div class="chip-row">\(badges)</div>
                <div class="meta"><span>LICENSE: \(license)</span><span>Updated: \(updated)</span></div>
                <h1 class="repo">\(html(context.ref.fullName))</h1>
                <div class="url">\(html(context.ref.url))</div>
                <div class="status" id="status">● \(statusText)</div>
                <div class="quick">
                  <div class="metric"><b>\(stars)</b><span>Stars</span></div>
                  <div class="metric"><b>\(forks)</b><span>Forks</span></div>
                  <div class="metric"><b>\(primary)</b><span>Primary</span></div>
                </div>
              </section>

              <div class="panel" id="panel-overview">
                <div class="section-title">Ask</div>
                <button class="row" onclick="native('summary')"><span class="icon">ⓘ</span><span class="title">Quick Summary</span></button>
                <button class="row" onclick="native('ask-mode')"><span class="icon">●</span><span class="title">Ask AI</span></button>
                <div class="section-title">Install with AI</div>
                <button class="row" onclick="native('claude')"><span class="icon">◆</span><span class="title">Claude Code</span></button>
                <button class="row" onclick="native('cursor')"><span class="icon">▶</span><span class="title">Cursor</span></button>
                <button class="row" onclick="native('codex')"><span class="icon">✽</span><span class="title">Codex</span></button>
                <button class="row accent" onclick="native('custom')"><span class="icon">+</span><span class="title">Add custom tool</span></button>
              </div>

              <div class="panel hidden" id="panel-codex">
                <div class="section-title">Codex workflow</div>
                <button class="row" onclick="native('codex')"><span class="icon">↵</span><span class="title">Run Codex analysis</span></button>
                <button class="row" onclick="native('summary')"><span class="icon">ⓘ</span><span class="title">Quick Summary</span></button>
                <button class="row" onclick="native('copy-url')"><span class="icon">⌘</span><span class="title">Copy repo URL</span></button>
              </div>

              <div class="panel hidden" id="panel-claude">
                <div class="section-title">Claude workflow</div>
                <button class="row" onclick="native('claude')"><span class="icon">↵</span><span class="title">Run Claude Code</span></button>
                <button class="row" onclick="native('ask-mode')"><span class="icon">●</span><span class="title">Ask AI here first</span></button>
                <button class="row" onclick="native('copy-url')"><span class="icon">⌘</span><span class="title">Copy repo URL</span></button>
              </div>

              <div class="panel hidden" id="panel-cursor">
                <div class="section-title">Cursor workflow</div>
                <button class="row" onclick="native('cursor')"><span class="icon">▶</span><span class="title">Open clone in Cursor</span></button>
                <button class="row" onclick="native('copy-url')"><span class="icon">⌘</span><span class="title">Copy repo URL</span></button>
                <div class="signal-card">
                  <h3>Root files</h3>
                  <p>\(files.isEmpty ? (isLoadingContext ? "Root files are loading." : "No root files loaded.") : files)</p>
                </div>
              </div>

              <div class="panel hidden" id="panel-tools">
                <div class="section-title">Tools</div>
                <button class="row accent" onclick="native('custom')"><span class="icon">+</span><span class="title">Add custom tool</span></button>
                <button class="row" onclick="native('settings')"><span class="icon">⚙</span><span class="title">Settings</span></button>
                <button class="row" onclick="native('share')"><span class="icon">▣</span><span class="title">Share repo</span><small>copy</small></button>
              </div>

              <div class="signal-card">
                <div class="chip-row" style="margin-bottom:9px">\(topics)</div>
                <h3>Quick signals</h3>
                <p><b>Stack:</b> \(stack)</p>
                <p style="margin-top:7px"><b>README:</b> \(readmeSignal)</p>
                <p style="margin-top:7px"><b>About:</b> \(description)</p>
              </div>

              <section class="detail hidden" id="detail">
                <h3 id="detail-title"></h3>
                <pre id="detail-body"></pre>
              </section>

              <section class="chat hidden" id="chat">
                <h3>Ask AI</h3>
                <div class="chat-log" id="chat-log"></div>
                <div class="askbar">
                  <input id="question" placeholder="Ask about this repo..." onkeydown="if(event.key==='Enter') askQuestion()">
                  <button class="send" onclick="askQuestion()">Ask</button>
                </div>
              </section>
            </main>
          </div>
          <script>
            function native(action, payload = {}) {
              window.webkit.messageHandlers.askyourgit.postMessage(Object.assign({ action }, payload));
            }
            document.querySelectorAll('.tab').forEach(tab => {
              tab.addEventListener('click', () => {
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                document.querySelectorAll('.panel').forEach(p => p.classList.add('hidden'));
                document.getElementById('panel-' + tab.dataset.tab).classList.remove('hidden');
                hideTransient();
              });
            });
            function hideTransient() {
              document.getElementById('detail').classList.add('hidden');
              document.getElementById('chat').classList.add('hidden');
            }
            function setStatus(text) {
              document.getElementById('status').textContent = '● ' + text;
            }
            function showDetail(title, text) {
              document.getElementById('chat').classList.add('hidden');
              document.getElementById('detail-title').textContent = title;
              document.getElementById('detail-body').textContent = text;
              document.getElementById('detail').classList.remove('hidden');
            }
            function showChat(initial) {
              document.getElementById('detail').classList.add('hidden');
              const chat = document.getElementById('chat');
              const log = document.getElementById('chat-log');
              if (!log.dataset.ready) {
                appendMessage('assistant', initial);
                log.dataset.ready = '1';
              }
              chat.classList.remove('hidden');
              document.getElementById('question').focus();
            }
            function appendMessage(role, text) {
              const node = document.createElement('div');
              node.className = 'msg ' + role;
              node.textContent = text;
              const log = document.getElementById('chat-log');
              log.appendChild(node);
              log.scrollTop = log.scrollHeight;
            }
            function askQuestion() {
              const input = document.getElementById('question');
              const question = input.value.trim();
              if (!question) return;
              input.value = '';
              appendMessage('user', question);
              native('ask', { question });
            }
          </script>
        </body>
        </html>
        """
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

    private func initialChatText() -> String {
        if isLoadingContext {
            return """
            I am loading \(context.ref.fullName) from GitHub now.

            Ask your question and I will answer after README, languages, topics, and files are ready.
            """
        }

        return """
        Ready. I analyzed \(context.ref.fullName).

        Ask about weak points, setup, stack, files, architecture, or next actions.
        """
    }

    private func settingsText() -> String {
        """
        Desktop companion: Connected
        Bridge: installed from the menu bar app
        Repo detection: active browser tab, then open GitHub/GitLab/Bitbucket tabs

        Use Install Browser Bridge from the menu to refresh native messaging.
        """
    }

    private func answer(for question: String) -> String {
        if !hasRepoContext {
            let reason = loadError ?? "Repository metadata is still unavailable."
            return """
            I could not load rich GitHub context for \(context.ref.fullName) yet.

            Reason:
            \(reason)

            I can still use the URL:
            \(context.ref.url)
            """
        }

        let lower = question.lowercased()
        if lower.contains("weak") || lower.contains("risk") || lower.contains("problem") || lower.contains("issue") || lower.contains("bug") || lower.contains("риск") || lower.contains("проблем") {
            return """
            Weak points to inspect first:

            1. Setup reliability: can a new user run it from README only?
            2. Runtime assumptions: env vars, local services, auth, and browser permissions.
            3. Tests for the main workflow.
            4. UI timing: anything that depends on page reloads or active browser state.

            Stack signal:
            \(context.languageSummary)
            """
        }
        if lower.contains("install") || lower.contains("run") || lower.contains("setup") || lower.contains("установ") || lower.contains("запуск") {
            return """
            Practical setup path:

            1. Clone \(context.ref.url)
            2. Read README first.
            3. Inspect root files: \(context.files.prefix(16).joined(separator: ", "))
            4. If package.json exists, check scripts for dev, build, and test commands.
            """
        }
        if lower.contains("file") || lower.contains("structure") || lower.contains("архит") || lower.contains("файл") || lower.contains("структ") {
            return "Root structure:\n\n\(context.files.prefix(42).joined(separator: ", "))"
        }
        if lower.contains("stack") || lower.contains("language") || lower.contains("tech") || lower.contains("язык") || lower.contains("стек") {
            return "Detected stack:\n\n\(context.languageSummary)\n\nPrimary language: \(context.primaryLanguage ?? "unknown")."
        }
        return """
        Summary:
        \(context.description ?? "No GitHub description available.")

        Key signals:
        - Languages: \(context.languageSummary)
        - Topics: \(context.topics.isEmpty ? "none found" : context.topics.prefix(10).joined(separator: ", "))
        - Root files: \(context.files.prefix(18).joined(separator: ", "))
        """
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
    }

    private func openCursor() {
        let repo = "\(context.ref.url).git"
        let encodedRepo = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
        let value = "cursor://vscode.git/clone?url=\(encodedRepo)"
        if let url = URL(string: value), NSWorkspace.shared.open(url) {
            return
        }
        copyToPasteboard(repo)
    }

    private func currentBadges() -> [String] {
        var badges = context.languages.prefix(2).map { $0.name }
        if badges.isEmpty, let primary = context.primaryLanguage {
            badges = [primary]
        }
        if context.files.contains(where: { $0.lowercased().contains("docker") }) {
            badges.append("Docker")
        }
        return badges.isEmpty ? ["GitHub"] : Array(badges.prefix(4))
    }

    private var hasRepoContext: Bool {
        context.description != nil ||
            context.primaryLanguage != nil ||
            !context.languages.isEmpty ||
            !context.files.isEmpty ||
            context.readme != nil ||
            context.stars != nil ||
            context.forks != nil
    }

    private var shouldWaitForContextBeforeAnswering: Bool {
        repoRef.host == "github.com" && !hasRepoContext && loadError == nil
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

    private func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
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

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}

final class ReferenceRepoAnalysisWindowController: NSWindowController, NSTextFieldDelegate {
    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private var selectedTab = "overview"
    private var chatTranscript = ""
    private var chatStarted = false
    private var tabButtons: [String: NSButton] = [:]
    private var bodyConstraints: [NSLayoutConstraint] = []
    private weak var lastBodyView: NSView?

    private let bodyContainer = NSView()
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
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.backgroundColor = backgroundColor
        window.contentMinSize = NSSize(width: 430, height: 640)
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

        let tabBar = makeTabBar()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBar)

        let divider = makeDivider()
        divider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(divider)

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyContainer)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            tabBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            tabBar.heightAnchor.constraint(equalToConstant: 74),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),

            bodyContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            bodyContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            bodyContainer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 14),
            bodyContainer.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
        ])

        configureTextView(panelTextView, size: 13, weight: .regular)
        configureInputRow()
        selectTab("overview")
    }

    private func makeTabBar() -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .fillEqually
        bar.spacing = 8

        let tabs = [
            ("overview", "square.grid.2x2.fill", "Overview"),
            ("codex", "circle.hexagongrid.fill", "Codex"),
            ("claude", "sparkle", "Claude"),
            ("cursor", "play.fill", "Cursor"),
            ("tools", "arrow.left.arrow.right", "Tools"),
        ]

        for tab in tabs {
            let button = NSButton(title: tab.2, target: self, action: #selector(tabClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tab.0)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.image = NSImage(systemSymbolName: tab.1, accessibilityDescription: tab.2)
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyDown
            button.heightAnchor.constraint(equalToConstant: 66).isActive = true
            tabButtons[tab.0] = button
            bar.addArrangedSubview(button)
        }

        return bar
    }

    @objc private func tabClicked(_ sender: NSButton) {
        selectTab(sender.identifier?.rawValue ?? "overview")
    }

    private func selectTab(_ id: String) {
        selectedTab = id
        updateTabs()
        render()
    }

    private func updateTabs() {
        let titles = [
            "overview": "Overview",
            "codex": "Codex",
            "claude": "Claude",
            "cursor": "Cursor",
            "tools": "Tools",
        ]

        for (id, button) in tabButtons {
            let selected = id == selectedTab
            button.layer?.backgroundColor = selected ? orangeColor.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? NSColor.white : mutedTextColor
            button.attributedTitle = NSAttributedString(
                string: titles[id] ?? id,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: selected ? NSColor.white : mutedTextColor,
                ]
            )
        }
    }

    private func render() {
        clearBody()
        resizeWindow(height: 640)

        switch selectedTab {
        case "codex":
            renderTool(title: "Codex", symbol: "circle.hexagongrid.fill", runTitle: "Run Codex", action: #selector(openCodex))
        case "claude":
            renderTool(title: "Claude Code", symbol: "sparkle", runTitle: "Run Claude Code", action: #selector(openClaudeCode))
        case "cursor":
            renderTool(title: "Cursor", symbol: "play.fill", runTitle: "Open in Cursor", action: #selector(openCursor))
        case "tools":
            addBodyView(makeActionRow(symbol: "plus", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
            addBodyView(makeDivider(), top: 8)
            addBodyView(makeActionRow(symbol: "gearshape.fill", title: "Settings", action: #selector(openSettings)), top: 8)
            addBodyView(makeActionRow(symbol: "dice.fill", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))
        default:
            addBodyView(makeHeader())
            addBodyView(makeDivider(), top: 10)
            addBodyView(makeActionRow(symbol: "info.circle.fill", title: "Quick Summary", action: #selector(showQuickSummary)), top: 8)
            addBodyView(makeActionRow(symbol: "bubble.left.fill", title: "Ask AI", action: #selector(showAskAI)))
            addBodyView(makeDivider(), top: 8)
            addBodyView(makeActionRow(symbol: "diamond.fill", title: "Claude Code", action: #selector(openClaudeCode)), top: 8)
            addBodyView(makeActionRow(symbol: "play.fill", title: "Cursor", action: #selector(openCursor)))
            addBodyView(makeActionRow(symbol: "circle.hexagongrid.fill", title: "Codex", action: #selector(openCodex)))
            addBodyView(makeActionRow(symbol: "plus", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
            addBodyView(makeDivider(), top: 8)
            addBodyView(makeActionRow(symbol: "gearshape.fill", title: "Settings", action: #selector(openSettings)), top: 8)
            addBodyView(makeActionRow(symbol: "dice.fill", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))
        }
    }

    private func renderTool(title: String, symbol: String, runTitle: String, action: Selector) {
        addBodyView(makeToolHero(title: title, symbol: symbol))
        addBodyView(makeActionRow(symbol: "return", title: runTitle, action: action), top: 10)
        addBodyView(makeActionRow(symbol: "doc.on.doc", title: "Copy repo URL", action: #selector(copyRepoURL)))
        addBodyView(makeActionRow(symbol: "info.circle.fill", title: "Quick Summary", action: #selector(showQuickSummary)))
        addBodyView(makeActionRow(symbol: "bubble.left.fill", title: "Ask AI", action: #selector(showAskAI)))
    }

    private func clearBody() {
        NSLayoutConstraint.deactivate(bodyConstraints)
        bodyConstraints.removeAll()
        for view in bodyContainer.subviews {
            view.removeFromSuperview()
        }
        lastBodyView = nil
        detailCard.removeFromSuperview()
        inputRow.removeFromSuperview()
    }

    private func addBodyView(_ view: NSView, top: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(view)
        let topAnchor = lastBodyView?.bottomAnchor ?? bodyContainer.topAnchor
        let constraints = [
            view.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor, constant: top),
        ]
        NSLayoutConstraint.activate(constraints)
        bodyConstraints.append(contentsOf: constraints)
        lastBodyView = view
    }

    private func makeHeader() -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 140).isActive = true

        let badges = NSStackView()
        badges.orientation = .horizontal
        badges.alignment = .leading
        badges.spacing = 8
        badges.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(badges)
        currentBadges().forEach { badges.addArrangedSubview(makeBadge($0)) }

        let metaLabel = makeLabel("LICENSE: \(context.license ?? "LICENSE")   Updated: \(formattedDate(context.updatedAt) ?? "Updated just now")", size: 13, weight: .semibold, color: mutedTextColor)
        let repoLabel = makeLabel(context.ref.fullName, size: 20, weight: .bold, color: textColor)
        let urlLabel = makeLabel(context.ref.url, size: 12, weight: .medium, color: mutedTextColor)
        let statusLabel = makeLabel("Ready", size: 13, weight: .bold, color: greenColor)

        [metaLabel, repoLabel, urlLabel, statusLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }

        NSLayoutConstraint.activate([
            badges.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            badges.topAnchor.constraint(equalTo: header.topAnchor),

            metaLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            metaLabel.topAnchor.constraint(equalTo: badges.bottomAnchor, constant: 12),

            repoLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            repoLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            repoLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),

            urlLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            urlLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            urlLabel.topAnchor.constraint(equalTo: repoLabel.bottomAnchor, constant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 8),
        ])

        return header
    }

    private func configureInputRow() {
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8
        inputRow.heightAnchor.constraint(equalToConstant: 40).isActive = true

        questionField.placeholderString = "Ask about this repo..."
        questionField.font = NSFont.systemFont(ofSize: 14)
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

        askButton.target = self
        askButton.action = #selector(askQuestion)
        askButton.isBordered = false
        askButton.wantsLayer = true
        askButton.layer?.backgroundColor = orangeColor.cgColor
        askButton.layer?.cornerRadius = 9
        askButton.attributedTitle = NSAttributedString(
            string: "Ask",
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.white]
        )
        askButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        inputRow.addArrangedSubview(questionField)
        inputRow.addArrangedSubview(askButton)
        questionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func loadContext() {
        Task {
            do {
                let loaded = try await GitHubRepoLoader.fetch(ref: repoRef)
                await MainActor.run {
                    self.context = loaded
                    self.render()
                }
            } catch {
                await MainActor.run {
                    self.render()
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
        if !chatStarted { showAskAI() }
        questionField.stringValue = ""
        appendMessage("You", question)
        appendMessage("Ask your GIT", answer(for: question))
    }

    private func showDetail(title: String, body: String, showsInput: Bool) {
        removeDetailViews()
        resizeWindow(height: showsInput ? 760 : 720)
        detailTitleLabel.stringValue = title
        panelTextView.string = body
        addBodyView(makeDetailCard(), top: 10)
        if showsInput {
            addBodyView(inputRow, top: 8)
        }
    }

    private func removeDetailViews() {
        if detailCard.superview != nil {
            detailCard.removeFromSuperview()
        }
        if inputRow.superview != nil {
            inputRow.removeFromSuperview()
        }
    }

    private func appendMessage(_ sender: String, _ text: String) {
        let separator = chatTranscript.hasSuffix("\n") ? "" : "\n"
        chatTranscript = chatTranscript + separator + "\n\(sender):\n\(text)\n"
        showDetail(title: "Ask AI", body: chatTranscript, showsInput: true)
        panelTextView.scrollToEndOfDocument(nil)
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

            Stack signal:
            \(context.languageSummary)
            """
        }
        if lower.contains("install") || lower.contains("run") || lower.contains("setup") || lower.contains("установ") || lower.contains("запуск") {
            return """
            Practical setup path:

            1. Clone \(context.ref.url)
            2. Read README first.
            3. Inspect root files: \(context.files.prefix(16).joined(separator: ", "))
            4. If package.json exists, check scripts for dev, build, and test commands.
            """
        }
        if lower.contains("file") || lower.contains("structure") || lower.contains("архит") || lower.contains("файл") || lower.contains("структ") {
            return "Root structure:\n\n\(context.files.prefix(42).joined(separator: ", "))"
        }
        if lower.contains("stack") || lower.contains("language") || lower.contains("tech") || lower.contains("язык") || lower.contains("стек") {
            return "Detected stack:\n\n\(context.languageSummary)\n\nPrimary language: \(context.primaryLanguage ?? "unknown")."
        }
        return """
        Summary:
        \(context.description ?? "No GitHub description available.")

        Key signals:
        - Languages: \(context.languageSummary)
        - Topics: \(context.topics.isEmpty ? "none found" : context.topics.prefix(10).joined(separator: ", "))
        - Root files: \(context.files.prefix(18).joined(separator: ", "))
        """
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
            return
        }
        copyToPasteboard(repo)
    }

    @objc private func addCustomTool() {
        showDetail(title: "Custom Tool", body: "Prototype slot for a custom local command template.", showsInput: false)
    }

    @objc private func openSettings() {
        showDetail(title: "Settings", body: "Desktop companion: Connected\nBridge: installed from the menu bar app\nRepo detection: active browser tab", showsInput: false)
    }

    @objc private func shareRepo() {
        copyToPasteboard("\(context.ref.fullName) \(context.ref.url)")
    }

    @objc private func copyRepoURL() {
        copyToPasteboard(context.ref.url)
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
    }

    private func makeActionRow(symbol: String, title: String, badge: String? = nil, accent: Bool = false, action: Selector) -> NSView {
        CompactActionRow(symbol: symbol, title: title, badge: badge, accent: accent, target: self, action: action)
    }

    private func makeToolHero(title: String, symbol: String) -> NSView {
        let hero = NSView()
        hero.wantsLayer = true
        hero.layer?.backgroundColor = cardColor.cgColor
        hero.layer?.cornerRadius = 10
        hero.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        icon.contentTintColor = textColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(icon)

        let titleLabel = makeLabel(title, size: 18, weight: .bold, color: textColor)
        let subtitle = makeLabel("Analyze \(context.ref.fullName) with this tool.", size: 12, weight: .medium, color: mutedTextColor)
        [titleLabel, subtitle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            hero.addSubview($0)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: hero.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
        ])
        return hero
    }

    private func makeDetailCard() -> NSView {
        if detailCard.subviews.isEmpty {
            detailCard.wantsLayer = true
            detailCard.layer?.backgroundColor = cardColor.cgColor
            detailCard.layer?.borderColor = borderColor.cgColor
            detailCard.layer?.borderWidth = 1
            detailCard.layer?.cornerRadius = 12
            detailCard.heightAnchor.constraint(equalToConstant: 180).isActive = true

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .width
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            detailCard.addSubview(stack)

            detailTitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
            detailTitleLabel.textColor = textColor
            stack.addArrangedSubview(detailTitleLabel)

            panelScrollView.hasVerticalScroller = true
            panelScrollView.hasHorizontalScroller = false
            panelScrollView.drawsBackground = false
            panelScrollView.borderType = .noBorder
            panelScrollView.documentView = panelTextView
            panelScrollView.heightAnchor.constraint(equalToConstant: 142).isActive = true
            stack.addArrangedSubview(panelScrollView)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: detailCard.topAnchor, constant: 10),
                stack.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor, constant: -10),
            ])
        }
        return detailCard
    }

    private func configureTextView(_ textView: NSTextView, size: CGFloat, weight: NSFont.Weight) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.font = NSFont.systemFont(ofSize: size, weight: weight)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
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

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        return label
    }

    private func currentBadges() -> [String] {
        var badges = context.languages.prefix(2).map { $0.name }
        if badges.isEmpty, let primary = context.primaryLanguage {
            badges = [primary]
        }
        if context.files.contains(where: { $0.lowercased().contains("docker") }) {
            badges.append("Docker")
        }
        return badges.isEmpty ? ["GitHub"] : Array(badges.prefix(4))
    }

    private func resizeWindow(height: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        let targetWidth: CGFloat = 430
        let delta = height - frame.height
        frame.origin.y -= delta
        frame.size.height = height
        frame.size.width = targetWidth
        window.setFrame(frame, display: true, animate: true)
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

final class CompactRepoAnalysisWindowController: NSWindowController, NSTextFieldDelegate {
    private let repoRef: RepoRef
    private var context: RepoAnalysisContext
    private var chatTranscript = ""
    private var chatStarted = false
    private var selectedTab = "overview"
    private var tabButtons: [String: NSButton] = [:]

    private let badgeStack = NSStackView()
    private let metaLabel = NSTextField(labelWithString: "Loading repo metadata...")
    private let repoLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Analyzing...")

    private let detailCard = NSView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let panelTextView = NSTextView()
    private let panelScrollView = NSScrollView()
    private let bodyStack = NSStackView()
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
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask your GIT"
        window.backgroundColor = backgroundColor
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 430, height: 640)
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

        root.addArrangedSubview(makeTabBar())
        root.addArrangedSubview(makeDivider())

        configureTextView(panelTextView, size: 13, weight: .regular)
        bodyStack.orientation = .vertical
        bodyStack.alignment = .width
        bodyStack.spacing = 8
        root.addArrangedSubview(bodyStack)

        refreshBadges()
        refreshMeta()
        selectTab("overview")
    }

    private func makeTabBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.distribution = .fillEqually
        bar.spacing = 8

        let tabs = [
            ("overview", "square.grid.2x2.fill", "Overview"),
            ("codex", "circle.hexagongrid.fill", "Codex"),
            ("claude", "sparkle", "Claude"),
            ("cursor", "play.fill", "Cursor"),
            ("tools", "arrow.left.arrow.right", "Tools"),
        ]

        for tab in tabs {
            let button = NSButton(title: "", target: self, action: #selector(tabClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tab.0)
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 10
            button.heightAnchor.constraint(equalToConstant: 58).isActive = true
            button.image = NSImage(systemSymbolName: tab.1, accessibilityDescription: tab.2)
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyDown
            button.attributedTitle = NSAttributedString(
                string: tab.2,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: mutedTextColor,
                ]
            )
            tabButtons[tab.0] = button
            bar.addArrangedSubview(button)
        }

        return bar
    }

    @objc private func tabClicked(_ sender: NSButton) {
        selectTab(sender.identifier?.rawValue ?? "overview")
    }

    private func selectTab(_ id: String) {
        selectedTab = id
        updateTabs()
        renderSelectedTab()
    }

    private func updateTabs() {
        for (id, button) in tabButtons {
            let selected = id == selectedTab
            button.layer?.backgroundColor = selected ? orangeColor.cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? NSColor.white : mutedTextColor
            let title = button.identifier?.rawValue == "overview" ? "Overview"
                : button.identifier?.rawValue == "codex" ? "Codex"
                : button.identifier?.rawValue == "claude" ? "Claude"
                : button.identifier?.rawValue == "cursor" ? "Cursor"
                : "Tools"
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: selected ? NSColor.white : mutedTextColor,
                ]
            )
        }
    }

    private func renderSelectedTab() {
        clearBody()
        switch selectedTab {
        case "codex":
            renderToolTab(title: "Codex", symbol: "circle.hexagongrid.fill", runTitle: "Run Codex", action: #selector(openCodex))
        case "claude":
            renderToolTab(title: "Claude Code", symbol: "sparkle", runTitle: "Run Claude Code", action: #selector(openClaudeCode))
        case "cursor":
            renderToolTab(title: "Cursor", symbol: "play.fill", runTitle: "Open in Cursor", action: #selector(openCursor))
        case "tools":
            bodyStack.addArrangedSubview(makeActionRow(symbol: "plus", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
            bodyStack.addArrangedSubview(makeDivider())
            bodyStack.addArrangedSubview(makeActionRow(symbol: "gearshape.fill", title: "Settings", action: #selector(openSettings)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "dice.fill", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))
        default:
            bodyStack.addArrangedSubview(makeHeader())
            bodyStack.addArrangedSubview(makeDivider())
            bodyStack.addArrangedSubview(makeActionRow(symbol: "info.circle.fill", title: "Quick Summary", action: #selector(showQuickSummary)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "bubble.left.fill", title: "Ask AI", action: #selector(showAskAI)))
            bodyStack.addArrangedSubview(makeDivider())
            bodyStack.addArrangedSubview(makeActionRow(symbol: "diamond.fill", title: "Claude Code", action: #selector(openClaudeCode)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "play.fill", title: "Cursor", action: #selector(openCursor)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "circle.hexagongrid.fill", title: "Codex", action: #selector(openCodex)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "plus", title: "Add custom tool", accent: true, action: #selector(addCustomTool)))
            bodyStack.addArrangedSubview(makeDivider())
            bodyStack.addArrangedSubview(makeActionRow(symbol: "gearshape.fill", title: "Settings", action: #selector(openSettings)))
            bodyStack.addArrangedSubview(makeActionRow(symbol: "dice.fill", title: "Share NFT", badge: "Animals", action: #selector(shareRepo)))
        }
    }

    private func renderToolTab(title: String, symbol: String, runTitle: String, action: Selector) {
        bodyStack.addArrangedSubview(makeToolHero(title: title, symbol: symbol))
        bodyStack.addArrangedSubview(makeActionRow(symbol: "return", title: runTitle, action: action))
        bodyStack.addArrangedSubview(makeActionRow(symbol: "doc.on.doc", title: "Copy repo URL", action: #selector(copyRepoURL)))
        bodyStack.addArrangedSubview(makeActionRow(symbol: "info.circle.fill", title: "Quick Summary", action: #selector(showQuickSummary)))
        bodyStack.addArrangedSubview(makeActionRow(symbol: "bubble.left.fill", title: "Ask AI", action: #selector(showAskAI)))
    }

    private func clearBody() {
        for view in bodyStack.arrangedSubviews {
            bodyStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        detailCard.removeFromSuperview()
        inputRow.removeFromSuperview()
        detailCard.isHidden = true
        inputRow.isHidden = true
        resizeWindow(height: 640)
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
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
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
                    if self.selectedTab == "overview" && !self.chatStarted {
                        self.renderSelectedTab()
                    } else if self.chatStarted {
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

    @objc private func copyRepoURL() {
        copyToPasteboard(context.ref.url)
        statusLabel.stringValue = "Repo URL copied"
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
        resizeWindow(height: showsInput ? 760 : 700)
        if detailCard.superview == nil {
            bodyStack.addArrangedSubview(detailCard.subviews.isEmpty ? makeDetailCard() : detailCard)
        }
        detailTitleLabel.stringValue = title
        panelTextView.string = body
        detailCard.isHidden = false
        if showsInput, inputRow.superview == nil {
            bodyStack.addArrangedSubview(inputRow.arrangedSubviews.isEmpty ? configureInputRow() : inputRow)
        }
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

    private func makeActionRow(symbol: String, title: String, badge: String? = nil, accent: Bool = false, action: Selector) -> NSView {
        CompactActionRow(symbol: symbol, title: title, badge: badge, accent: accent, target: self, action: action)
    }

    private func makeToolHero(title: String, symbol: String) -> NSView {
        let hero = NSView()
        hero.wantsLayer = true
        hero.layer?.backgroundColor = cardColor.cgColor
        hero.layer?.cornerRadius = 10

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(stack)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        iconView.contentTintColor = textColor
        iconView.widthAnchor.constraint(equalToConstant: 34).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 34).isActive = true
        stack.addArrangedSubview(iconView)

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        stack.addArrangedSubview(copy)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = textColor
        copy.addArrangedSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "Analyze \(context.ref.fullName) with this tool.")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = mutedTextColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        copy.addArrangedSubview(subtitle)

        NSLayoutConstraint.activate([
            hero.heightAnchor.constraint(equalToConstant: 70),
            stack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: hero.centerYAnchor),
        ])

        return hero
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
