//
//  StatusbarCountdownTests.swift
//  StatusbarCountdownTests
//
//  Created by Ben Brooks on 31/03/2015.
//  Copyright (c) 2015 Ben Brooks. All rights reserved.
//

import Cocoa

@main
struct TestRunner {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fputs("❌ FAILED: \(message) — expected '\(expected)', got '\(actual)'\n", stderr)
            exit(1)
        } else {
            print("✅ PASSED: \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("❌ FAILED: \(message)\n", stderr)
            exit(1)
        } else {
            print("✅ PASSED: \(message)")
        }
    }

    static func main() {
        print("Running StatusbarCountdown & CCFDeadline Unit Tests...")

        // 1. Test secondsToTime decomposition
        let t1 = CountdownFormatter.secondsToTime(90061)
        assertEqual(t1.0, 1, "secondsToTime days for 90061s")
        assertEqual(t1.1, 1, "secondsToTime hours for 90061s")
        assertEqual(t1.2, 1, "secondsToTime minutes for 90061s")
        assertEqual(t1.3, 1, "secondsToTime seconds for 90061s")

        // 2. Test formatTime variations
        assertEqual(CountdownFormatter.formatTime(90061, showSeconds: true, zeroPad: false), "1d 1h 1m 1s", "formatTime basic")
        assertEqual(CountdownFormatter.formatTime(90061, showSeconds: true, zeroPad: true), "1d 01h 01m 01s", "formatTime zeroPad")
        assertEqual(CountdownFormatter.formatTime(90061, showSeconds: false, zeroPad: false), "1d 1h 1m", "formatTime no seconds")
        assertEqual(CountdownFormatter.formatTime(-3665, showSeconds: true, zeroPad: false), "1h 1m 5s ago", "formatTime past")
        assertEqual(CountdownFormatter.formatTime(42, showSeconds: false, zeroPad: false), "0m", "formatTime sub-minute no seconds")

        // 3. Test CCF AoE & UTC offset timezone resolution
        let aoeTz = CCFDeadlineParser.resolveTimeZone("AoE")
        assertEqual(aoeTz.secondsFromGMT(), -12 * 3600, "AoE resolves to UTC-12")

        let utc8Tz = CCFDeadlineParser.resolveTimeZone("UTC+8")
        assertEqual(utc8Tz.secondsFromGMT(), 8 * 3600, "UTC+8 resolves to +28800s")

        // 4. Test AoE deadline date parsing
        let dtAoE = CCFDeadlineParser.parseDeadlineDate("2026-11-25 23:59:59", timezoneString: "AoE")
        let dtUTC = CCFDeadlineParser.parseDeadlineDate("2026-11-26 11:59:59", timezoneString: "UTC+0")
        assertEqual(dtAoE, dtUTC, "2026-11-25 23:59:59 AoE equals 2026-11-26 11:59:59 UTC")

        // 5. Test built-in CCF YAML parser
        let parsedConfs = CCFDeadlineParser.parseYAML(CCFDeadlineRepository.builtInPopularConferencesYAML)
        assertTrue(parsedConfs.count >= 8, "Built-in YAML parses at least 8 top conferences")
        let iclr = parsedConfs.first(where: { $0.title == "ICLR" })
        assertEqual(iclr?.ccfRank, "A", "ICLR has CCF-A rank")
        assertEqual(iclr?.activeEdition()?.rounds.first?.rebuttalDeadline, "2026-11-25 23:59:59", "ICLR rebuttal deadline parsed")

        print("🎉 All 15 unit assertions passed!")
    }
}
