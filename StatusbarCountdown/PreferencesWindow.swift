//
//  PreferencesWindow.swift
//  StatusbarCountdown
//
//  Created by Jacqueline Alves on 02/10/19.
//  Copyright © 2019 Ben Brooks. All rights reserved.
//

import Cocoa
import SwiftUI

final class PreferencesViewModel: ObservableObject {
    @Published var name: String = "" {
        didSet {
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameError = false
            }
        }
    }
    @Published var targetDate: Date = Date().addingTimeInterval(3600) {
        didSet {
            if targetDate > Date() {
                dateError = false
            }
        }
    }
    @Published var nameError: Bool = false
    @Published var dateError: Bool = false

    // Paper & CCF Conference Tracking State
    @Published var searchQuery: String = ""
    @Published var selectedCategory: String = "ALL"
    @Published var selectedConference: CCFConferenceSeries?
    @Published var selectedStage: PaperStage = .submission
    @Published var selectedTimezoneNote: String = ""
    @Published var selectedConferenceLink: String = ""
    @Published var selectedCCFRank: String = ""
    @Published var trackedItems: [TrackedCountdownItem] = []
    @Published var calendarFeedbackMessage: String = ""
    @Published var pendingDeleteItemId: UUID? = nil

    func loadFromDefaults(defaultName: String, defaultDate: Date) {
        let defaults = UserDefaults.standard
        let savedName = defaults.string(forKey: "name") ?? defaultName
        let savedDate = defaults.object(forKey: "date") as? Date ?? defaultDate
        self.name = savedName
        if savedDate > Date() {
            self.targetDate = savedDate
        } else {
            self.targetDate = Date().addingTimeInterval(86400)
        }
        self.selectedTimezoneNote = defaults.string(forKey: "timezoneNote") ?? ""
        self.selectedConferenceLink = defaults.string(forKey: "conferenceLink") ?? ""
        self.selectedCCFRank = defaults.string(forKey: "ccfRank") ?? ""
        self.nameError = false
        self.dateError = false
        loadTrackedItems()
    }

    func loadTrackedItems() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "trackedCountdowns"),
           let decoded = try? JSONDecoder().decode([TrackedCountdownItem].self, from: data) {
            self.trackedItems = decoded
        }
    }

    func saveTrackedItems() {
        if let encoded = try? JSONEncoder().encode(trackedItems) {
            UserDefaults.standard.set(encoded, forKey: "trackedCountdowns")
        }
    }

    func applyConference(_ series: CCFConferenceSeries, stage: PaperStage? = nil) {
        self.selectedConference = series
        let activeStage = stage ?? self.selectedStage
        self.selectedStage = activeStage
        self.selectedCCFRank = series.ccfRank

        guard let ed = series.activeEdition() else {
            self.name = "\(series.title) \(activeStage.rawValue)"
            return
        }

        let shortYear = String(format: "%02d", ed.year % 100)
        self.name = "\(series.title) '\(shortYear) \(activeStage.rawValue)"
        self.selectedConferenceLink = ed.link ?? ""

        let round = ed.rounds.first
        let tzStr = round?.timezone ?? ed.timezone

        var rawDateStr: String?
        switch activeStage {
        case .abstract:
            rawDateStr = round?.abstractDeadline ?? round?.submissionDeadline
        case .submission:
            rawDateStr = round?.submissionDeadline ?? round?.abstractDeadline
        case .rebuttal:
            rawDateStr = round?.rebuttalDeadline
        case .decision:
            rawDateStr = round?.decisionDeadline
        case .cameraReady:
            rawDateStr = nil
        }

        if let dateStr = rawDateStr,
           let parsedDate = CCFDeadlineParser.parseDeadlineDate(dateStr, timezoneString: tzStr) {
            self.targetDate = parsedDate
            self.selectedTimezoneNote = "\(dateStr) (\(tzStr))"
        } else if let subStr = round?.submissionDeadline,
                  let subDate = CCFDeadlineParser.parseDeadlineDate(subStr, timezoneString: tzStr) {
            // Estimate stage relative to paper submission deadline if not explicitly in YAML
            switch activeStage {
            case .abstract:
                self.targetDate = subDate.addingTimeInterval(-7 * 86400)
                self.selectedTimezoneNote = "Est. -7d before Paper (\(tzStr))"
            case .rebuttal:
                self.targetDate = subDate.addingTimeInterval(60 * 86400)
                self.selectedTimezoneNote = "Est. +60d after Paper (\(tzStr)) — adjust as needed"
            case .decision:
                self.targetDate = subDate.addingTimeInterval(90 * 86400)
                self.selectedTimezoneNote = "Est. +90d after Paper (\(tzStr)) — adjust as needed"
            case .cameraReady:
                self.targetDate = subDate.addingTimeInterval(115 * 86400)
                self.selectedTimezoneNote = "Est. +115d after Paper (\(tzStr)) — adjust as needed"
            case .submission:
                self.targetDate = subDate
                self.selectedTimezoneNote = "\(subStr) (\(tzStr))"
            }
        }
    }

    func addCurrentToTracked() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Avoid exact duplicate names; update existing if same name
        if let idx = trackedItems.firstIndex(where: { $0.name == trimmed }) {
            trackedItems[idx].targetDate = targetDate
            trackedItems[idx].timezoneString = selectedTimezoneNote
            trackedItems[idx].link = selectedConferenceLink
            trackedItems[idx].ccfRank = selectedCCFRank
        } else {
            let item = TrackedCountdownItem(
                name: trimmed,
                targetDate: targetDate,
                conferenceTitle: selectedConference?.title,
                stage: selectedStage.rawValue,
                timezoneString: selectedTimezoneNote,
                rawDeadlineString: selectedTimezoneNote,
                link: selectedConferenceLink,
                ccfRank: selectedCCFRank
            )
            trackedItems.append(item)
        }
        saveTrackedItems()
    }

    func removeTracked(_ item: TrackedCountdownItem) {
        trackedItems.removeAll { $0.id == item.id }
        saveTrackedItems()
    }

    func exportCurrentToCalendar() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let exportTitle = trimmed.isEmpty ? "Paper Deadline" : trimmed
        CalendarService.exportDeadlineToCalendar(
            title: exportTitle,
            deadlineDate: targetDate,
            timezoneNote: selectedTimezoneNote,
            conferenceLink: selectedConferenceLink,
            ccfRank: selectedCCFRank
        ) { [weak self] result in
            switch result {
            case .savedDirectly(let msg), .openedICS(let msg):
                self?.calendarFeedbackMessage = "✅ " + msg
            case .failed(let err):
                self?.calendarFeedbackMessage = "⚠️ " + err
            }
        }
    }
}

struct PreferencesContentView: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @ObservedObject var repository = CCFDeadlineRepository.shared
    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var now = Date()
    private let previewTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let categories = ["ALL", "AI", "SE", "DB", "NW", "SC", "DS", "CG", "HI", "CT", "MX"]

    private var filteredConferences: [CCFConferenceSeries] {
        repository.conferences.filter { conf in
            let matchesCat = (viewModel.selectedCategory == "ALL") || (conf.sub.uppercased() == viewModel.selectedCategory)
            let q = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = q.isEmpty
                || conf.title.localizedCaseInsensitiveContains(q)
                || conf.description.localizedCaseInsensitiveContains(q)
            return matchesCat && matchesQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)

                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("Paper & CCF Deadline Countdown")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Text("v2.0")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                            .fixedSize()
                    }

                    Text(repository.lastSyncMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer()

                Button {
                    repository.syncFromCloud()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: repository.isSyncing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                        Text(repository.isSyncing ? "Syncing" : "Sync CCF")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(repository.isSyncing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().opacity(0.6)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {

                    // 1. CCF Conference Quick Picker Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("1. Select CCF / Top Conference (一键选顶会)", systemImage: "sparkles")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            if let conf = viewModel.selectedConference, !conf.ccfRank.isEmpty, conf.ccfRank != "N" {
                                Text("CCF-\(conf.ccfRank)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.2)))
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        // Category Filter + Search Bar
                        HStack(spacing: 8) {
                            Picker("", selection: $viewModel.selectedCategory) {
                                ForEach(categories, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 78)

                            TextField("Search NeurIPS, ICLR, CVPR, ACL, OSDI...", text: $viewModel.searchQuery)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12.5))
                        }

                        // Horizontal Scrollable Chips of Conferences
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(filteredConferences.prefix(35)) { series in
                                    let isSelected = viewModel.selectedConference?.id == series.id
                                    Button {
                                        viewModel.applyConference(series)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(series.title)
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            if series.ccfRank == "A" {
                                                Text("A")
                                                    .font(.system(size: 9.5, weight: .bold))
                                                    .padding(.horizontal, 3.5)
                                                    .padding(.vertical, 0.5)
                                                    .background(Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15)))
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                                        )
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        // Stage Segmented Buttons (Abstract / Paper / Rebuttal / Decision / Camera-Ready)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Submission Stage (一键切换阶段):")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 6) {
                                ForEach(PaperStage.allCases) { stage in
                                    let active = viewModel.selectedStage == stage
                                    Button {
                                        if let conf = viewModel.selectedConference {
                                            viewModel.applyConference(conf, stage: stage)
                                        } else {
                                            viewModel.selectedStage = stage
                                            let base = viewModel.name
                                                .replacingOccurrences(of: " Abstract", with: "")
                                                .replacingOccurrences(of: " Paper", with: "")
                                                .replacingOccurrences(of: " Rebuttal", with: "")
                                                .replacingOccurrences(of: " Decision", with: "")
                                                .replacingOccurrences(of: " Camera-Ready", with: "")
                                            viewModel.name = "\(base) \(stage.rawValue)"
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: stage.iconName)
                                                .font(.system(size: 10.5))
                                            Text(stage.rawValue)
                                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                                .lineLimit(1)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(active ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 1)
                                        )
                                        .foregroundStyle(active ? Color.accentColor : Color.primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    // 2. Event Name & Custom Target Date/Time
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("2. Countdown Title & Exact Target (支持自定义修改)", systemImage: "calendar.badge.clock")
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            if viewModel.nameError {
                                Text("Name can't be empty")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .systemRed))
                            } else if viewModel.dateError {
                                Text("Date must be in the future")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .systemRed))
                            }
                        }

                        TextField("e.g. ICLR '27 Rebuttal, NeurIPS '26 Paper", text: $viewModel.name)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .font(.system(size: 13))

                        HStack(spacing: 14) {
                            HStack(spacing: 6) {
                                Text("Local Date:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                DatePicker("", selection: $viewModel.targetDate, displayedComponents: [.date])
                                    .labelsHidden()
                                    .datePickerStyle(.stepperField)
                            }

                            HStack(spacing: 6) {
                                Text("Local Time:")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                DatePicker("", selection: $viewModel.targetDate, displayedComponents: [.hourAndMinute])
                                    .labelsHidden()
                                    .datePickerStyle(.stepperField)
                            }

                            Spacer()
                        }

                        if !viewModel.selectedTimezoneNote.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "globe.americas.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("Conf Timezone: \(viewModel.selectedTimezoneNote) → Auto-converted to your Local Time")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("Quick Adjust:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                            PresetButton(title: "+1h") {
                                viewModel.targetDate = max(Date(), viewModel.targetDate).addingTimeInterval(3600)
                            }
                            PresetButton(title: "+1d") {
                                viewModel.targetDate = max(Date(), viewModel.targetDate).addingTimeInterval(86400)
                            }
                            PresetButton(title: "+7d") {
                                viewModel.targetDate = max(Date(), viewModel.targetDate).addingTimeInterval(86400 * 7)
                            }
                            Spacer()
                            Button {
                                viewModel.exportCurrentToCalendar()
                            } label: {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                viewModel.addCurrentToTracked()
                            } label: {
                                Label("Pin to Menu", systemImage: "pin.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !viewModel.calendarFeedbackMessage.isEmpty {
                            Text(viewModel.calendarFeedbackMessage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    // 3. Pinned Multi-Deadline Watchlist (if any)
                    if !viewModel.trackedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Pinned Deadlines in Menubar Dropdown (多会议快捷切换列表)", systemImage: "list.bullet.rectangle")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(viewModel.trackedItems) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(CountdownFormatter.formatTime(Int(item.targetDate.timeIntervalSince(now)), showSeconds: false, zeroPad: false))
                                        .font(.system(size: 11.5).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Button {
                                        viewModel.name = item.name
                                        viewModel.targetDate = item.targetDate
                                        viewModel.selectedTimezoneNote = item.timezoneString ?? ""
                                    } label: {
                                        Text("Use")
                                            .font(.system(size: 10.5))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)

                                    Button {
                                        CalendarService.exportDeadlineToCalendar(
                                            title: item.name,
                                            deadlineDate: item.targetDate,
                                            timezoneNote: item.timezoneString,
                                            conferenceLink: item.link,
                                            ccfRank: item.ccfRank
                                        ) { result in
                                            if case .openedICS(let msg) = result {
                                                viewModel.calendarFeedbackMessage = "✅ " + msg
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(.system(size: 11))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Add this deadline to Calendar")

                                    if viewModel.pendingDeleteItemId == item.id {
                                        Button(role: .destructive) {
                                            viewModel.removeTracked(item)
                                            viewModel.pendingDeleteItemId = nil
                                        } label: {
                                            Text("Confirm Delete?")
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .foregroundStyle(Color(nsColor: .systemRed))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    } else {
                                        Button {
                                            viewModel.pendingDeleteItemId = item.id
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Click twice to remove")
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            }
                        }
                    }

                    // 4. Live Menubar Preview Pill
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)

                        Text("Menubar Preview:")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(livePreviewText)
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider().opacity(0.6)

            // Footer Actions
            HStack(spacing: 10) {
                if !viewModel.selectedConferenceLink.isEmpty,
                   let url = URL(string: viewModel.selectedConferenceLink) {
                    Link(destination: url) {
                        Label("Conference Website", systemImage: "safari")
                            .font(.system(size: 12))
                    }
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

                Button("Save and Start") {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 540, height: 610)
        .background(VisualEffectBlur())
        .onReceive(previewTimer) { currentTime in
            self.now = currentTime
        }
    }

    private var livePreviewText: String {
        let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Countdown Name" : trimmedName
        let diff = Int(viewModel.targetDate.timeIntervalSince(now))
        return "\(displayName): \(CountdownFormatter.formatTime(diff, showSeconds: true, zeroPad: false))"
    }
}

private struct PresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

class PreferencesWindow: NSWindowController, NSWindowDelegate {

    var delegate: PreferencesWindowDelegate?
    private let viewModel = PreferencesViewModel()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 610),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Paper & CCF Deadline Preferences"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        self.init(window: window)
        window.delegate = self

        let contentView = PreferencesContentView(
            viewModel: viewModel,
            onSave: { [weak self] in
                self?.validate(nil)
            },
            onCancel: { [weak self] in
                self?.closePopover(nil)
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        window.contentViewController = hostingController
    }

    override func showWindow(_ sender: Any?) {
        let defaultDate = Date().addingTimeInterval(86400 * 7)
        viewModel.loadFromDefaults(defaultName: "ICLR '27 Rebuttal", defaultDate: defaultDate)

        super.showWindow(sender)
        self.window?.center()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func save() {
        let defaults = UserDefaults.standard
        let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)

        defaults.set(trimmedName, forKey: "name")
        defaults.set(viewModel.targetDate, forKey: "date")
        defaults.set(viewModel.selectedTimezoneNote, forKey: "timezoneNote")
        defaults.set(viewModel.selectedConferenceLink, forKey: "conferenceLink")
        defaults.set(viewModel.selectedCCFRank, forKey: "ccfRank")

        // Automatically pin the active countdown to the watchlist if not present
        viewModel.addCurrentToTracked()

        delegate?.preferencesDidUpdate()
    }

    @IBAction func validate(_ sender: Any?) {
        var validation = true

        if viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.nameError = true
            window?.shakeWindow()
            validation = false
        }

        if viewModel.targetDate < Date() {
            viewModel.dateError = true
            window?.shakeWindow()
            validation = false
        }

        if validation {
            save()
            close()
        }
    }

    @IBAction func closePopover(_ sender: Any?) {
        close()
    }
}
