import XCTest
@testable import TrainingOS

@MainActor
final class SmartAlarmPlatformTests: XCTestCase {
    func testPlatformAvailability() {
#if targetEnvironment(macCatalyst)
        XCTAssertFalse(SmartAlarmService.isSupported)
        XCTAssertFalse(SmartAlarmService.shared.isEnabled)
        XCTAssertEqual(SmartAlarmService.shared.state, .unsupportedPlatform)
#elseif canImport(AlarmKit)
        XCTAssertTrue(SmartAlarmService.isSupported)
#endif
    }

#if targetEnvironment(macCatalyst)
    func testUnsupportedActionsNeverScheduleOrChangePersistedSettings() async {
        let service = SmartAlarmService.shared
        let originalWindow = [service.windowStartHour, service.windowStartMinute,
                              service.windowEndHour, service.windowEndMinute]
        let defaults = UserDefaults.standard
        let fixture: [String: Any] = [
            "smartAlarm.enabled": true,
            "smartAlarm.windowStartHH": 5,
            "smartAlarm.windowStartMM": 45,
            "smartAlarm.windowEndHH": 8,
            "smartAlarm.windowEndMM": 15,
            "smartAlarm.pendingAlarmID": UUID().uuidString,
            "smartAlarm.lastBedtimeTimestamp": 123456789.0
        ]
        let saved = fixture.keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for (key, value) in fixture { defaults.set(value, forKey: key) }

        await service.enable()
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.state, .unsupportedPlatform)
        await service.updateWindow(startHour: 9, startMinute: 10, endHour: 10, endMinute: 20)
        do {
            try await service.scheduleAlarm(bedtimeDate: Date())
            XCTFail("Catalyst must explicitly reject scheduling, never report success")
        } catch SmartAlarmError.unsupportedPlatform {
            // Expected: no AlarmKit call and no synthetic pending alarm.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        service.cancelAlarm()
        await service.disable()

        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.state, .unsupportedPlatform)
        XCTAssertEqual([service.windowStartHour, service.windowStartMinute,
                        service.windowEndHour, service.windowEndMinute], originalWindow)
        for (key, expected) in fixture {
            XCTAssertEqual(defaults.object(forKey: key) as? NSObject, expected as? NSObject, key)
        }
        XCTAssertEqual(SmartAlarmError.unsupportedPlatform.errorDescription, "Disponible sur iPhone/iPad")
    }
#endif
}
