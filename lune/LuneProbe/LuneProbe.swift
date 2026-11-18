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
///   noidle                         stop waiting for the app's animations to settle after each event,
///                                  so a following burst can catch transitions mid-flight
///   burst <name> <count>           screenshots back to back, as fast as the device allows
///   tapburst <count> <label>       tap an element while a background thread bursts screenshots,
///                                  so the first frames land before and during the tap
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
        case "noidle":
            Self.skipQuiescence()
        case "tapburst":
            let words = rest.split(separator: " ", maxSplits: 1).map(String.init)
            let count = Int(words[0]) ?? 16
            let label = words.count > 1 ? words[1] : ""
            let predicate = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
            let element = app.descendants(matching: .any).matching(predicate).firstMatch
            guard element.waitForExistence(timeout: 3) else { return XCTFail("no element \(label)") }
            let frame = element.frame
            let target = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            let collector = BurstCollector()
            let start = Date()
            let done = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                for _ in 0..<count {
                    collector.append(Date().timeIntervalSince(start), XCUIScreen.main.screenshot())
                }
                done.signal()
            }
            Thread.sleep(forTimeInterval: 0.15)
            let tapAt = Date().timeIntervalSince(start)
            target.tap()
            done.wait()
            for (frame, (time, shot)) in collector.shots.enumerated() {
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = String(format: "%02d-tb-%02d-%+05dms", index, frame, Int((time - tapAt) * 1000))
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        case "burst":
            let words = rest.split(separator: " ").map(String.init)
            let count = words.count > 1 ? Int(words[1]) ?? 10 : 10
            let start = Date()
            var shots: [(Double, XCUIScreenshot)] = []
            for _ in 0..<count {
                shots.append((Date().timeIntervalSince(start), XCUIScreen.main.screenshot()))
            }
            for (frame, (time, shot)) in shots.enumerated() {
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = String(format: "%02d-%@-%02d-%04dms", index, words.first ?? "burst", frame, Int(time * 1000))
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        default:
            XCTFail("unknown command \(command)")
        }
    }

    /// XCTest blocks after every event until the app's animations finish, which hides transitions.
    /// Replacing the private wait with a no-op lets screenshots land during the animation.
    private static func skipQuiescence() {
        guard let process = NSClassFromString("XCUIApplicationProcess") else { return }
        let block: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
        let blockPre: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
        for (name, implementation) in [
            ("waitForQuiescenceIncludingAnimationsIdle:", imp_implementationWithBlock(block)),
            ("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", imp_implementationWithBlock(blockPre)),
        ] {
            if let method = class_getInstanceMethod(process, NSSelectorFromString(name)) {
                method_setImplementation(method, implementation)
            }
        }
    }

    @MainActor
    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }
}

private final class BurstCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shots: [(Double, XCUIScreenshot)] = []

    func append(_ time: Double, _ shot: XCUIScreenshot) {
        lock.lock()
        shots.append((time, shot))
        lock.unlock()
    }
}
