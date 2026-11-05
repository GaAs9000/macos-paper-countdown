//
//  CCFDeadlineService.swift
//  StatusbarCountdown
//
//  Native CCF Deadlines (ccfddl) YAML Parser, Timezone Converter & Paper Stage Presets.
//

import Cocoa
import Foundation

public enum PaperStage: String, CaseIterable, Identifiable {
    case abstract = "Abstract"
    case submission = "Paper"
    case rebuttal = "Rebuttal"
    case decision = "Decision"
    case cameraReady = "Camera-Ready"

    public var id: String { rawValue }

    public var bilingualTitle: String {
        switch self {
        case .abstract: return "Abstract / 摘要"
        case .submission: return "Paper / 全文"
        case .rebuttal: return "Rebuttal / 反驳"
        case .decision: return "Decision / 录用通知"
        case .cameraReady: return "Camera-Ready / 终稿"
        }
    }

    public var iconName: String {
        switch self {
        case .abstract: return "doc.text"
        case .submission: return "paperplane.fill"
        case .rebuttal: return "bubble.left.and.exclamationmark.bubble.right.fill"
        case .decision: return "bell.badge.fill"
        case .cameraReady: return "checkmark.seal.fill"
        }
    }
}

public struct CCFTimelineRound: Identifiable, Equatable {
    public let id = UUID()
    public var abstractDeadline: String?
    public var submissionDeadline: String?
    public var decisionDeadline: String?
    public var rebuttalDeadline: String?
    public var comment: String?
    public var timezone: String?
}

public struct CCFConferenceEdition: Identifiable, Equatable {
    public var id: String
    public var year: Int
    public var link: String?
    public var timezone: String
    public var dateText: String?
    public var place: String?
    public var rounds: [CCFTimelineRound]
}

public struct CCFConferenceSeries: Identifiable, Equatable {
    public var id: String { "\(sub)_\(title)" }
    public var title: String
    public var description: String
    public var sub: String
    public var ccfRank: String
    public var coreRank: String
    public var editions: [CCFConferenceEdition]

    /// Returns the most relevant edition (prefers the earliest edition with future deadlines, otherwise the latest edition by year).
    public func activeEdition(at referenceDate: Date = Date()) -> CCFConferenceEdition? {
        let sorted = editions.sorted { $0.year < $1.year }
        for ed in sorted {
            for round in ed.rounds {
                let tz = round.timezone ?? ed.timezone
                if let subStr = round.submissionDeadline,
                   let dt = CCFDeadlineParser.parseDeadlineDate(subStr, timezoneString: tz),
                   dt > referenceDate {
                    return ed
                }
                if let absStr = round.abstractDeadline,
                   let dt = CCFDeadlineParser.parseDeadlineDate(absStr, timezoneString: tz),
                   dt > referenceDate {
                    return ed
                }
            }
        }
        return sorted.last
    }
}

public struct TrackedCountdownItem: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var targetDate: Date
    public var conferenceTitle: String?
    public var stage: String?
    public var timezoneString: String?
    public var rawDeadlineString: String?
    public var link: String?
    public var ccfRank: String?
}

public enum CalendarExportResult {
    case savedDirectly(String)
    case openedICS(String)
    case failed(String)
}

public enum CalendarService {
    /// Export a countdown deadline to Apple Calendar (or default `.ics` handler) with automatic 7-day, 1-day, and 1-hour advance alarms.
    public static func exportDeadlineToCalendar(
        title: String,
        deadlineDate: Date,
        timezoneNote: String?,
        conferenceLink: String?,
        ccfRank: String?,
        completion: @escaping (CalendarExportResult) -> Void
    ) {
        // Always generate a rich standard .ics with VALARM reminders and open in Calendar.app
        // Using standard .ics guarantees zero TCC entitlement friction on ad-hoc signed builds AND works with Apple Calendar, Outlook, or Fantastical.
        do {
            let icsURL = try generateICSFile(
                title: title,
                deadlineDate: deadlineDate,
                timezoneNote: timezoneNote,
                conferenceLink: conferenceLink,
                ccfRank: ccfRank
            )
            NSWorkspace.shared.open(icsURL)
            completion(.openedICS("Opened '\(title)' in Calendar (with 7d / 1d / 1h reminders)"))
        } catch {
            completion(.failed("Failed to export calendar event: \(error.localizedDescription)"))
        }
    }

    public static func generateICSFile(
        title: String,
        deadlineDate: Date,
        timezoneNote: String?,
        conferenceLink: String?,
        ccfRank: String?
    ) throws -> URL {
        let utcFormatter = DateFormatter()
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        // Set event start 1 hour before deadline and end right at the exact deadline
        let startDate = deadlineDate.addingTimeInterval(-3600)
        let dtStamp = utcFormatter.string(from: Date())
        let dtStart = utcFormatter.string(from: startDate)
        let dtEnd = utcFormatter.string(from: deadlineDate)
        let uid = UUID().uuidString + "@statusbarcountdown.macos"

        let rankBadge = (ccfRank != nil && !ccfRank!.isEmpty && ccfRank != "N") ? " [CCF-\(ccfRank!)]" : ""
        let summary = escapeICS("⏰ \(title)\(rankBadge) Deadline")

        var descLines: [String] = ["Paper & CCF Conference Deadline Reminder"]
        if let tz = timezoneNote, !tz.isEmpty {
            descLines.append("Conference Origin Timezone: \(tz)")
        }
        if let link = conferenceLink, !link.isEmpty {
            descLines.append("Official Website: \(link)")
        }
        let description = escapeICS(descLines.joined(separator: "\\n"))
        let urlLine = (conferenceLink != nil && !conferenceLink!.isEmpty) ? "\r\nURL:\(conferenceLink!)" : ""

        let icsContent = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        PRODID:-//StatusbarCountdown//Paper & CCF Deadline Countdown v2.1//EN\r
        CALSCALE:GREGORIAN\r
        METHOD:PUBLISH\r
        BEGIN:VEVENT\r
        UID:\(uid)\r
        DTSTAMP:\(dtStamp)\r
        DTSTART:\(dtStart)\r
        DTEND:\(dtEnd)\r
        SUMMARY:\(summary)\r
        DESCRIPTION:\(description)\(urlLine)\r
        STATUS:CONFIRMED\r
        BEGIN:VALARM\r
        TRIGGER:-P7D\r
        ACTION:DISPLAY\r
        DESCRIPTION:\(summary) is in 7 days!\r
        END:VALARM\r
        BEGIN:VALARM\r
        TRIGGER:-P1D\r
        ACTION:DISPLAY\r
        DESCRIPTION:\(summary) is tomorrow (24 hours left)!\r
        END:VALARM\r
        BEGIN:VALARM\r
        TRIGGER:-PT1H\r
        ACTION:DISPLAY\r
        DESCRIPTION:\(summary) is in 1 hour!\r
        END:VALARM\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let safeFileName = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(safeFileName)_Deadline.ics")
        try icsContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func escapeICS(_ text: String) -> String {
        return text
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }
}

public enum CCFDeadlineParser {

    /// Convert ccfddl timezone strings ("AoE", "UTC-12", "UTC+8", "UTC", or IANA zone names) into a `TimeZone`.
    public static func resolveTimeZone(_ raw: String?) -> TimeZone {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return TimeZone(secondsFromGMT: 0)!
        }
        if raw.uppercased() == "AOE" {
            return TimeZone(secondsFromGMT: -12 * 3600)!
        }
        if raw.uppercased() == "UTC" {
            return TimeZone(secondsFromGMT: 0)!
        }

        // Match UTC+8, UTC-5, UTC+05:30, etc.
        let upper = raw.uppercased()
        if upper.hasPrefix("UTC") {
            let offsetPart = String(upper.dropFirst(3))
            if offsetPart.isEmpty {
                return TimeZone(secondsFromGMT: 0)!
            }
            let sign: Int = offsetPart.hasPrefix("-") ? -1 : 1
            let clean = offsetPart.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            let comps = clean.split(separator: ":")
            if let hours = Int(comps.first ?? "") {
                let minutes = comps.count > 1 ? (Int(comps[1]) ?? 0) : 0
                let totalSeconds = sign * (hours * 3600 + minutes * 60)
                if let tz = TimeZone(secondsFromGMT: totalSeconds) {
                    return tz
                }
            }
        }

        if let iana = TimeZone(identifier: raw) {
            return iana
        }
        return TimeZone(secondsFromGMT: 0)!
    }

    /// Parse a ccfddl deadline string ("YYYY-MM-DD HH:mm:ss" or "YYYY-MM-DD HH:mm") in its conference timezone into an absolute `Date`.
    public static func parseDeadlineDate(_ dateStr: String, timezoneString: String?) -> Date? {
        let trimmed = dateStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "TBD" else { return nil }

        let tz = resolveTimeZone(timezoneString)
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = tz

        for fmt in formats {
            df.dateFormat = fmt
            if let dt = df.date(from: trimmed) {
                return dt
            }
        }
        return nil
    }

    /// Strip inline YAML comments outside quotes.
    private static func stripInlineComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "'" && !inDouble {
                inSingle.toggle()
            } else if c == "\"" && !inSingle {
                let escaped = i > 0 && chars[i - 1] == "\\"
                if !escaped { inDouble.toggle() }
            } else if c == "#" && !inSingle && !inDouble {
                if i == 0 || chars[i - 1].isWhitespace {
                    return String(chars[0..<i]).trimmingCharacters(in: .whitespaces)
                }
            }
            i += 1
        }
        return line.trimmingCharacters(in: .newlines)
    }

    private static func unquote(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2 {
            if (s.hasPrefix("'") && s.hasSuffix("'")) || (s.hasPrefix("\"") && s.hasSuffix("\"")) {
                return String(s.dropFirst().dropLast())
            }
        }
        return s
    }

    private static func splitKeyValue(_ text: String) -> (String, String)? {
        guard let colonIdx = text.firstIndex(of: ":") else { return nil }
        let key = String(text[..<colonIdx]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        let valStart = text.index(after: colonIdx)
        let val = unquote(String(text[valStart...]))
        return (key, val)
    }

    /// Pure Swift parser for `ccfddl` conference YAML files (`allconf.yml` or individual `<conf>.yml`).
    public static func parseYAML(_ content: String) -> [CCFConferenceSeries] {
        var seriesList: [CCFConferenceSeries] = []

        var curTitle = ""
        var curDesc = ""
        var curSub = ""
        var curCCFRank = ""
        var curCoreRank = ""
        var curEditions: [CCFConferenceEdition] = []

        var inSeries = false
        var inRank = false
        var inTimeline = false

        var curEdition: CCFConferenceEdition?
        var curRound: CCFTimelineRound?

        func flushRound() {
            if let r = curRound {
                curEdition?.rounds.append(r)
                curRound = nil
            }
        }

        func flushEdition() {
            flushRound()
            if let ed = curEdition {
                curEditions.append(ed)
                curEdition = nil
            }
        }

        func flushSeries() {
            flushEdition()
            if inSeries && !curTitle.isEmpty {
                seriesList.append(
                    CCFConferenceSeries(
                        title: curTitle,
                        description: curDesc,
                        sub: curSub,
                        ccfRank: curCCFRank.isEmpty ? "N" : curCCFRank,
                        coreRank: curCoreRank,
                        editions: curEditions
                    )
                )
            }
            curTitle = ""
            curDesc = ""
            curSub = ""
            curCCFRank = ""
            curCoreRank = ""
            curEditions = []
            inRank = false
            inTimeline = false
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let cleaned = stripInlineComment(rawLine)
            let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let indent = cleaned.prefix(while: { $0 == " " }).count

            if trimmed.hasPrefix("- ") {
                let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if indent == 0 {
                    flushSeries()
                    inSeries = true
                    if let (k, v) = splitKeyValue(afterDash), k == "title" {
                        curTitle = v
                    }
                    continue
                }

                if let (k, v) = splitKeyValue(afterDash) {
                    if k == "year" {
                        flushEdition()
                        inTimeline = false
                        let yr = Int(v) ?? 0
                        curEdition = CCFConferenceEdition(
                            id: "\(curTitle.lowercased())\(yr)",
                            year: yr,
                            link: nil,
                            timezone: "AoE",
                            dateText: nil,
                            place: nil,
                            rounds: []
                        )
                        continue
                    } else if inTimeline {
                        flushRound()
                        var newRound = CCFTimelineRound()
                        assignRoundField(&newRound, key: k, value: v)
                        curRound = newRound
                        continue
                    }
                }
                continue
            }

            guard let (k, v) = splitKeyValue(trimmed) else { continue }

            if inTimeline && curRound != nil && indent >= 6 {
                if var r = curRound {
                    assignRoundField(&r, key: k, value: v)
                    curRound = r
                    continue
                }
            }

            if curEdition != nil && indent >= 4 {
                if k == "timeline" {
                    flushRound()
                    inTimeline = true
                    continue
                }
                inTimeline = false
                switch k {
                case "id": curEdition?.id = v
                case "link": curEdition?.link = v
                case "timezone": curEdition?.timezone = v
                case "date": curEdition?.dateText = v
                case "place": curEdition?.place = v
                default: break
                }
                continue
            }

            // Series-level fields
            if k == "rank" {
                inRank = true
                continue
            }
            if k == "confs" {
                inRank = false
                continue
            }

            if inRank && indent >= 4 {
                if k == "ccf" { curCCFRank = v }
                if k == "core" { curCoreRank = v }
                continue
            }

            inRank = false
            switch k {
            case "title": curTitle = v
            case "description": curDesc = v
            case "sub": curSub = v
            default: break
            }
        }

        flushSeries()
        return seriesList
    }

    private static func assignRoundField(_ round: inout CCFTimelineRound, key: String, value: String) {
        switch key {
        case "abstract_deadline": round.abstractDeadline = value
        case "deadline": round.submissionDeadline = value
        case "decision_deadline": round.decisionDeadline = value
        case "rebuttal_deadline": round.rebuttalDeadline = value
        case "comment": round.comment = value
        case "timezone": round.timezone = value
        default: break
        }
    }
}

public final class CCFDeadlineRepository: ObservableObject {
    public static let shared = CCFDeadlineRepository()

    @Published public private(set) var conferences: [CCFConferenceSeries] = []
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncMessage: String = "Built-in + Cloud CCF Deadlines"

    private let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("StatusbarCountdown", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("allconf_cache.yml")
    }()

    private init() {
        loadInitialData()
    }

    public func loadInitialData() {
        if let cachedText = try? String(contentsOf: cacheURL, encoding: .utf8) {
            let parsed = CCFDeadlineParser.parseYAML(cachedText)
            if !parsed.isEmpty {
                self.conferences = Self.prioritizePopularConferences(parsed)
                self.lastSyncMessage = "Loaded \(parsed.count) conferences from local cache"
                return
            }
        }
        let fallback = CCFDeadlineParser.parseYAML(Self.builtInPopularConferencesYAML)
        self.conferences = Self.prioritizePopularConferences(fallback)
    }

    public func syncFromCloud(completion: ((Bool) -> Void)? = nil) {
        guard !isSyncing else { return }
        isSyncing = true
        lastSyncMessage = "Syncing from ccfddl.com..."

        let url = URL(string: "https://ccfddl.com/conference/allconf.yml")!
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSyncing = false

                guard let data = data, error == nil,
                      let yamlString = String(data: data, encoding: .utf8) else {
                    self.lastSyncMessage = "Offline mode (using built-in top conferences)"
                    completion?(false)
                    return
                }

                let parsed = CCFDeadlineParser.parseYAML(yamlString)
                guard !parsed.isEmpty else {
                    self.lastSyncMessage = "Failed to parse cloud YAML"
                    completion?(false)
                    return
                }

                try? yamlString.write(to: self.cacheURL, atomically: true, encoding: .utf8)
                self.conferences = Self.prioritizePopularConferences(parsed)
                let df = DateFormatter()
                df.timeStyle = .short
                self.lastSyncMessage = "Synced \(parsed.count) CCF conferences (\(df.string(from: Date())))"
                completion?(true)
            }
        }
        task.resume()
    }

    private static let featuredOrder: [String] = [
        "NeurIPS", "ICML", "ICLR", "CVPR", "ICCV", "ECCV", "ACL", "EMNLP", "NAACL",
        "AAAI", "IJCAI", "KDD", "WWW", "SIGIR", "ICSE", "FSE", "ASE", "ISSTA",
        "OSDI", "SOSP", "NSDI", "ASPLOS", "EuroSys", "SIGCOMM", "SIGMOD", "VLDB",
        "ICDE", "CCS", "USENIX Security", "S&P", "NDSS", "CHI", "UbiComp", "UIST"
    ]

    private static func prioritizePopularConferences(_ list: [CCFConferenceSeries]) -> [CCFConferenceSeries] {
        return list.sorted { a, b in
            let idxA = featuredOrder.firstIndex(where: { $0.caseInsensitiveCompare(a.title) == .orderedSame }) ?? Int.max
            let idxB = featuredOrder.firstIndex(where: { $0.caseInsensitiveCompare(b.title) == .orderedSame }) ?? Int.max
            if idxA != idxB { return idxA < idxB }
            if a.ccfRank != b.ccfRank { return a.ccfRank < b.ccfRank }
            return a.title < b.title
        }
    }

    /// Built-in curated seed YAML so the app works immediately offline.
    public static let builtInPopularConferencesYAML = """
    - title: NeurIPS
      description: Conference on Neural Information Processing Systems
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2026
          id: nips26
          link: https://neurips.cc/Conferences/2026
          timeline:
            - abstract_deadline: '2026-05-05 11:59:00'
              deadline: '2026-05-07 11:59:59'
              decision_deadline: '2026-09-25 11:59:59'
          timezone: UTC+0
          date: December 8-10, 2026
          place: Sydney / Atlanta / Paris
    - title: ICLR
      description: International Conference on Learning Representations
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: iclr27
          link: https://iclr.cc/
          timeline:
            - abstract_deadline: '2026-09-22 23:59:59'
              deadline: '2026-09-27 23:59:59'
              rebuttal_deadline: '2026-11-25 23:59:59'
              decision_deadline: '2027-01-22 23:59:59'
          timezone: AoE
          date: April 2027
          place: TBD
    - title: ICML
      description: International Conference on Machine Learning
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: icml27
          link: https://icml.cc/
          timeline:
            - abstract_deadline: '2027-01-23 23:59:59'
              deadline: '2027-01-30 23:59:59'
              rebuttal_deadline: '2027-03-28 23:59:59'
              decision_deadline: '2027-05-01 23:59:59'
          timezone: AoE
          date: July 2027
          place: TBD
    - title: CVPR
      description: IEEE/CVF Conference on Computer Vision and Pattern Recognition
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: cvpr27
          link: https://cvpr.thecvf.com/
          timeline:
            - abstract_deadline: '2026-11-08 23:59:59'
              deadline: '2026-11-15 23:59:59'
              rebuttal_deadline: '2027-01-26 23:59:59'
              decision_deadline: '2027-02-26 23:59:59'
          timezone: AoE
          date: June 2027
          place: TBD
    - title: ACL
      description: Annual Meeting of the Association for Computational Linguistics
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: acl27
          link: https://www.aclweb.org/
          timeline:
            - abstract_deadline: '2027-02-08 23:59:59'
              deadline: '2027-02-15 23:59:59'
              rebuttal_deadline: '2027-04-15 23:59:59'
              decision_deadline: '2027-05-15 23:59:59'
          timezone: AoE
          date: July 2027
          place: TBD
    - title: AAAI
      description: AAAI Conference on Artificial Intelligence
      sub: AI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: aaai27
          link: https://aaai.org/
          timeline:
            - abstract_deadline: '2026-08-07 23:59:59'
              deadline: '2026-08-15 23:59:59'
              rebuttal_deadline: '2026-11-04 23:59:59'
              decision_deadline: '2026-12-09 23:59:59'
          timezone: AoE
          date: February 2027
          place: TBD
    - title: KDD
      description: ACM SIGKDD Conference on Knowledge Discovery and Data Mining
      sub: DB
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: kdd27
          link: https://kdd.org/
          timeline:
            - abstract_deadline: '2027-02-03 23:59:59'
              deadline: '2027-02-10 23:59:59'
          timezone: AoE
          date: August 2027
          place: TBD
    - title: ICSE
      description: International Conference on Software Engineering
      sub: SE
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: icse27
          link: https://conf.researchr.org/home/icse-2027
          timeline:
            - abstract_deadline: '2026-07-25 23:59:59'
              deadline: '2026-08-01 23:59:59'
          timezone: AoE
          date: April 2027
          place: TBD
    - title: CHI
      description: ACM Conference on Human Factors in Computing Systems
      sub: HI
      rank:
        ccf: A
        core: A*
      confs:
        - year: 2027
          id: chi27
          link: https://chi.acm.org/
          timeline:
            - abstract_deadline: '2026-09-05 23:59:59'
              deadline: '2026-09-12 23:59:59'
          timezone: AoE
          date: May 2027
          place: TBD
    """
}
