import XCTest

/// Headless UI probe. Runs on the device and drives any installed app.
///
/// Pass a script through the environment when running tests:
///   TEST_RUNNER_PROBE_SCRIPT='launch company.thebrowser.ArcMobile2; wait 2; shot home'
///
/// Commands (separated by `;` or newlines). Coordinates are fractions of the screen (0...1).
///   launch <bundle-id> [args...]   terminate and relaunch the app
///   activate <bundle-id>           bring an app to the front without relaunching
///   shot <name>                    screenshot attachment
///   tree <name>                    accessibility hierarchy attachment
///   tap <x> <y>                    tap a point
///   tapel <label>                  tap the first element whose label or identifier matches
///   press <x> <y> [seconds]        long press
///   swipe <x1> <y1> <x2> <y2> [s]  drag between points (s = hold before moving, default 0.05)
///   flick <up|down|left|right>     fast system swipe on the app
///   type <text>                    type into the focused field
///   go <text>                      type, then press return
///   wait <seconds>                 sleep
final class LuneProbe: XCTestCase {
    private var app = XCUIApplication(bundleIdentifier: "sh.dunkirk.lune")

    @MainActor
    func testProbe() throws {
        continueAfterFailure = true
        let script = ProcessInfo.processInfo.environment["PROBE_SCRIPT"] ?? "launch sh.dunkirk.lune; shot lune"
        let steps = script
            .split(whereSeparator: { $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (index, step) in steps.enumerated() {
            let parts = step.split(separator: " ", maxSplits: 1).map(String.init)
            let command = parts[0]
            let rest = parts.count > 1 ? parts[1] : ""
            let numbers = rest.split(separator: " ").compactMap { Double($0) }
            XCTContext.runActivity(named: "\(index): \(step)") { _ in
                run(command, rest: rest, numbers: numbers, index: index)
            }
        }
    }

    @MainActor
    private func run(_ command: String, rest: String, numbers: [Double], index: Int) {
        switch command {
        case "launch":
            let words = rest.split(separator: " ").map(String.init)
            app = XCUIApplication(bundleIdentifier: words[0])
            app.launchArguments = Array(words.dropFirst())
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
        case "activate":
            app = XCUIApplication(bundleIdentifier: rest)
            app.activate()
            _ = app.wait(for: .runningForeground, timeout: 10)
        case "shot":
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = String(format: "%02d-%@", index, rest.isEmpty ? "shot" : rest)
            attachment.lifetime = .keepAlways
            add(attachment)
        case "tree":
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = String(format: "%02d-%@.txt", index, rest.isEmpty ? "tree" : rest)
            attachment.lifetime = .keepAlways
            add(attachment)
        case "tap":
            point(numbers[0], numbers[1]).tap()
        case "tapel":
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", rest, rest)
            let element = app.descendants(matching: .any).matching(predicate).firstMatch
            if element.waitForExistence(timeout: 3) {
                element.tap()
            } else {
                XCTFail("no element \(rest)")
            }
        case "press":
            point(numbers[0], numbers[1]).press(forDuration: numbers.count > 2 ? numbers[2] : 1)
        case "swipe":
            let hold = numbers.count > 4 ? numbers[4] : 0.05
            point(numbers[0], numbers[1]).press(forDuration: hold, thenDragTo: point(numbers[2], numbers[3]))
        case "flick":
            switch rest {
            case "up": app.swipeUp(velocity: .fast)
            case "down": app.swipeDown(velocity: .fast)
            case "left": app.swipeLeft(velocity: .fast)
            default: app.swipeRight(velocity: .fast)
            }
        case "type":
            app.typeText(rest)
        case "go":
            app.typeText(rest + "\n")
        case "wait":
            Thread.sleep(forTimeInterval: numbers.first ?? 1)
        default:
            XCTFail("unknown command \(command)")
        }
    }

    @MainActor
    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }
}
