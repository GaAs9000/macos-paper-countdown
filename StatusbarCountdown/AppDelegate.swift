//
//  AppDelegate.swift
//  StatusbarCountdown
//
//  Created by Ben Brooks on 31/03/2015.
//  Copyright (c) 2015 Ben Brooks. All rights reserved.
//

import Cocoa
import Foundation
import ServiceManagement

protocol PreferencesWindowDelegate: AnyObject {
    func preferencesDidUpdate()
}

enum CountdownFormatter {
    // Convert seconds to 4 Time integers (days, hours, minutes and seconds)
    static func secondsToTime(_ seconds: Int) -> (Int, Int, Int, Int) {
        let days = seconds / (3600 * 24)
        var remainder = seconds % (3600 * 24)

        let hours = remainder / 3600
        remainder = remainder % 3600

        let minutes = remainder / 60
        let secs = remainder % 60

        return (days, hours, minutes, secs)
    }

    // Display seconds as Days, Hours, Minutes, Seconds.
    static func formatTime(_ seconds: Int, showSeconds: Bool, zeroPad: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.minimumIntegerDigits = zeroPad ? 2 : 1

        let time = secondsToTime(abs(seconds))
        let daysStr = (time.0 != 0) ? String(time.0) + "d " : ""
        let hoursStr = (time.1 != 0 || time.0 != 0)
            ? (formatter.string(from: NSNumber(value: time.1)) ?? "\(time.1)") + "h "
            : ""
        let minutesStr = (time.2 != 0 || time.1 != 0 || time.0 != 0)
            ? (formatter.string(from: NSNumber(value: time.2)) ?? "\(time.2)") + "m"
            : ""
        let secondsStr: String
        if showSeconds {
            let prefix = (!daysStr.isEmpty || !hoursStr.isEmpty || !minutesStr.isEmpty) ? " " : ""
            secondsStr = prefix + (formatter.string(from: NSNumber(value: time.3)) ?? "\(time.3)") + "s"
        } else {
            secondsStr = (daysStr.isEmpty && hoursStr.isEmpty && minutesStr.isEmpty) ? "0m" : ""
        }
        let suffixStr = (seconds < 0) ? " ago" : ""
        return daysStr + hoursStr + minutesStr + secondsStr + suffixStr
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, PreferencesWindowDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    let DEFAULT_NAME = "ICLR '27 Rebuttal"
    let DEFAULT_DATE = Date().addingTimeInterval(86400 * 7)

    var countToDate = Date().addingTimeInterval(86400 * 7)
    var countdownName = "ICLR '27 Rebuttal"
    var timezoneNote = ""
    var conferenceLink = ""
    var ccfRank = ""
    var trackedItems: [TrackedCountdownItem] = []

    var showName = true
    var showSeconds = true
    var zeroPad = false
    var mascotStyle: MascotStyle = .cloud

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusMenu: NSMenu!
    var preferencesWindow: PreferencesWindow!

    private let dateDisplayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadDisplayToggles()

        preferencesWindow = PreferencesWindow()
        preferencesWindow.delegate = self

        setupStatusBarButton()
        updatePreferences()
        rebuildStatusMenu()
        tick()

        // Silently refresh CCF deadlines in the background on startup
        CCFDeadlineRepository.shared.syncFromCloud()

        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
    }

    private func loadDisplayToggles() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "showName") != nil {
            showName = defaults.bool(forKey: "showName")
        }
        if defaults.object(forKey: "showSeconds") != nil {
            showSeconds = defaults.bool(forKey: "showSeconds")
        }
        if defaults.object(forKey: "zeroPad") != nil {
            zeroPad = defaults.bool(forKey: "zeroPad")
        }
        if let savedMascot = defaults.string(forKey: "mascotStyle"),
           let style = MascotStyle(rawValue: savedMascot) {
            mascotStyle = style
        }
    }

    private func setupStatusBarButton() {
        guard let button = statusItem.button else { return }
        button.image = mascotStyle.makeStatusBarImage()
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    }

    func rebuildStatusMenu() {
        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false

        // 1. Active Target Header
        let rankBadge = (!ccfRank.isEmpty && ccfRank != "N") ? " [CCF-\(ccfRank)]" : ""
        let headerNameItem = NSMenuItem(title: countdownName + rankBadge, action: nil, keyEquivalent: "")
        headerNameItem.isEnabled = false
        if let tagIcon = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil) {
            tagIcon.isTemplate = true
            headerNameItem.image = tagIcon
        }
        statusMenu.addItem(headerNameItem)

        let localTzAbbrev = TimeZone.current.abbreviation() ?? "Local"
        let headerLocalDateItem = NSMenuItem(
            title: "Local: \(dateDisplayFormatter.string(from: countToDate)) (\(localTzAbbrev))",
            action: nil,
            keyEquivalent: ""
        )
        headerLocalDateItem.isEnabled = false
        if let calIcon = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil) {
            calIcon.isTemplate = true
            headerLocalDateItem.image = calIcon
        }
        statusMenu.addItem(headerLocalDateItem)

        if !timezoneNote.isEmpty {
            let confTzItem = NSMenuItem(
                title: "Origin: \(timezoneNote)",
                action: nil,
                keyEquivalent: ""
            )
            confTzItem.isEnabled = false
            if let globeIcon = NSImage(systemSymbolName: "globe.americas.fill", accessibilityDescription: nil) {
                globeIcon.isTemplate = true
                confTzItem.image = globeIcon
            }
            statusMenu.addItem(confTzItem)
        }

        if !conferenceLink.isEmpty {
            let webItem = NSMenuItem(
                title: "Open Conference Website…",
                action: #selector(openConferenceWebsite),
                keyEquivalent: ""
            )
            webItem.target = self
            if let safariIcon = NSImage(systemSymbolName: "safari", accessibilityDescription: nil) {
                safariIcon.isTemplate = true
                webItem.image = safariIcon
            }
            statusMenu.addItem(webItem)
        }

        let calReminderItem = NSMenuItem(
            title: "Add Deadline to Calendar…",
            action: #selector(addCurrentDeadlineToCalendar),
            keyEquivalent: "e"
        )
        calReminderItem.target = self
        if let calPlusIcon = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: nil) {
            calPlusIcon.isTemplate = true
            calReminderItem.image = calPlusIcon
        }
        statusMenu.addItem(calReminderItem)

        // 2. Pinned Multi-Deadline Quick Switcher
        if !trackedItems.isEmpty {
            statusMenu.addItem(NSMenuItem.separator())
            let sectionTitle = NSMenuItem(title: "Pinned Deadlines (Click to Switch)", action: nil, keyEquivalent: "")
            sectionTitle.isEnabled = false
            statusMenu.addItem(sectionTitle)

            for (index, item) in trackedItems.enumerated() {
                let diff = Int(item.targetDate.timeIntervalSinceNow)
                let rem = CountdownFormatter.formatTime(diff, showSeconds: false, zeroPad: false)
                let itemMenu = NSMenuItem(
                    title: "\(item.name) — \(rem)",
                    action: #selector(switchActiveTrackedItem(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                itemMenu.target = self
                itemMenu.tag = index
                itemMenu.state = (item.name == countdownName) ? .on : .off
                statusMenu.addItem(itemMenu)
            }
        }

        statusMenu.addItem(NSMenuItem.separator())

        // 3. Display Toggles
        let showNameMenuItem = NSMenuItem(
            title: "Show Name",
            action: #selector(toggleShowName(sender:)),
            keyEquivalent: ""
        )
        showNameMenuItem.target = self
        showNameMenuItem.state = showName ? .on : .off
        if let icon = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil) {
            icon.isTemplate = true
            showNameMenuItem.image = icon
        }
        statusMenu.addItem(showNameMenuItem)

        let showSecondsMenuItem = NSMenuItem(
            title: "Show Seconds",
            action: #selector(toggleShowSeconds(sender:)),
            keyEquivalent: ""
        )
        showSecondsMenuItem.target = self
        showSecondsMenuItem.state = showSeconds ? .on : .off
        if let icon = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: nil) {
            icon.isTemplate = true
            showSecondsMenuItem.image = icon
        }
        statusMenu.addItem(showSecondsMenuItem)

        let zeroPadMenuItem = NSMenuItem(
            title: "Leading Zeros",
            action: #selector(toggleZeroPad(sender:)),
            keyEquivalent: ""
        )
        zeroPadMenuItem.target = self
        zeroPadMenuItem.state = zeroPad ? .on : .off
        if let icon = NSImage(systemSymbolName: "00.square", accessibilityDescription: nil) {
            icon.isTemplate = true
            zeroPadMenuItem.image = icon
        }
        statusMenu.addItem(zeroPadMenuItem)

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(sender:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        if let icon = NSImage(systemSymbolName: "power.circle", accessibilityDescription: nil) {
            icon.isTemplate = true
            launchAtLoginItem.image = icon
        }
        statusMenu.addItem(launchAtLoginItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 4. Preferences & Cloud Sync
        let prefsItem = NSMenuItem(
            title: "Paper & CCF Preferences…",
            action: #selector(configurePreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        if let icon = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil) {
            icon.isTemplate = true
            prefsItem.image = icon
        }
        statusMenu.addItem(prefsItem)

        let syncItem = NSMenuItem(
            title: "Sync CCF Deadlines Now",
            action: #selector(syncCCFDeadlinesNow),
            keyEquivalent: "r"
        )
        syncItem.target = self
        if let icon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            icon.isTemplate = true
            syncItem.image = icon
        }
        statusMenu.addItem(syncItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApplication(sender:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        if let icon = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            icon.isTemplate = true
            quitItem.image = icon
        }
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    func preferencesDidUpdate() {
        updatePreferences()
        rebuildStatusMenu()
        tick()
    }

    func updatePreferences() {
        let defaults = UserDefaults.standard
        countdownName = defaults.string(forKey: "name") ?? DEFAULT_NAME
        if let savedDate = defaults.object(forKey: "date") as? Date {
            countToDate = savedDate
        } else {
            let initialDate = Date().addingTimeInterval(86400 * 7)
            countToDate = initialDate
            defaults.set(initialDate, forKey: "date")
        }
        timezoneNote = defaults.string(forKey: "timezoneNote") ?? ""
        conferenceLink = defaults.string(forKey: "conferenceLink") ?? ""
        ccfRank = defaults.string(forKey: "ccfRank") ?? ""

        if let data = defaults.data(forKey: "trackedCountdowns"),
           let decoded = try? JSONDecoder().decode([TrackedCountdownItem].self, from: data) {
            trackedItems = decoded
        } else {
            trackedItems = []
        }

        if let savedMascot = defaults.string(forKey: "mascotStyle"),
           let style = MascotStyle(rawValue: savedMascot) {
            mascotStyle = style
        }
        statusItem.button?.image = mascotStyle.makeStatusBarImage()
    }

    @objc func switchActiveTrackedItem(_ sender: NSMenuItem) {
        let idx = sender.tag
        guard idx >= 0 && idx < trackedItems.count else { return }
        let item = trackedItems[idx]

        let defaults = UserDefaults.standard
        defaults.set(item.name, forKey: "name")
        defaults.set(item.targetDate, forKey: "date")
        defaults.set(item.timezoneString ?? "", forKey: "timezoneNote")
        defaults.set(item.link ?? "", forKey: "conferenceLink")
        defaults.set(item.ccfRank ?? "", forKey: "ccfRank")

        updatePreferences()
        rebuildStatusMenu()
        tick()
    }

    @objc func openConferenceWebsite() {
        guard !conferenceLink.isEmpty, let url = URL(string: conferenceLink) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func addCurrentDeadlineToCalendar() {
        CalendarService.exportDeadlineToCalendar(
            title: countdownName,
            deadlineDate: countToDate,
            timezoneNote: timezoneNote,
            conferenceLink: conferenceLink,
            ccfRank: ccfRank
        ) { _ in }
    }

    @objc func syncCCFDeadlinesNow() {
        CCFDeadlineRepository.shared.syncFromCloud()
    }

    @objc func tick() {
        let diffSeconds = Int(countToDate.timeIntervalSinceNow)
        let formattedTime = formatTime(diffSeconds)

        guard let button = statusItem.button else { return }

        let fullString = showName ? "\(countdownName): \(formattedTime)" : formattedTime

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .medium),
            .paragraphStyle: paragraphStyle,
            .baselineOffset: -0.5
        ]

        let attrString = NSMutableAttributedString(string: " " + fullString, attributes: attributes)
        if showName {
            let nameRange = NSRange(location: 1, length: countdownName.count + 1)
            attrString.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: 13.0, weight: .regular),
                range: nameRange
            )
        }

        button.attributedTitle = attrString
    }

    func secondsToTime(_ seconds: Int) -> (Int, Int, Int, Int) {
        return CountdownFormatter.secondsToTime(seconds)
    }

    func formatTime(_ seconds: Int) -> String {
        return CountdownFormatter.formatTime(seconds, showSeconds: showSeconds, zeroPad: zeroPad)
    }

    @IBAction func toggleShowSeconds(sender: NSMenuItem) {
        showSeconds.toggle()
        sender.state = showSeconds ? .on : .off
        UserDefaults.standard.set(showSeconds, forKey: "showSeconds")
        tick()
    }

    @IBAction func toggleShowName(sender: NSMenuItem) {
        showName.toggle()
        sender.state = showName ? .on : .off
        UserDefaults.standard.set(showName, forKey: "showName")
        tick()
    }

    @IBAction func toggleZeroPad(sender: NSMenuItem) {
        zeroPad.toggle()
        sender.state = zeroPad ? .on : .off
        UserDefaults.standard.set(zeroPad, forKey: "zeroPad")
        tick()
    }

    @objc func toggleLaunchAtLogin(sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            NSSound.beep()
        }
    }

    @IBAction func configurePreferences(_ sender: Any) {
        preferencesWindow.showWindow(nil)
    }

    @IBAction func quitApplication(sender: NSMenuItem) {
        NSApplication.shared.terminate(self)
    }
}
