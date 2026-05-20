import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

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
            self.installBridge()
        }
    }

    private func makeMenuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func installBridge() {
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
                show("Bridge installed", "Ask your GIT can now send commands to your local tools.\n\nChrome extension folder:\n\(extensionURL.path)\n\nOpen chrome://extensions, enable Developer mode, then Load unpacked and select this folder.")
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

        let launchStatus = revealRepoTabAndTriggerAskYourGIT(url)
        if launchStatus == "triggered" {
            return
        } else if launchStatus == "opened" {
            return
        } else {
            show("Repo detected", "\(url)\n\nThe repo URL was copied. Click the Ask your GIT button on the page to analyze it.")
        }
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
