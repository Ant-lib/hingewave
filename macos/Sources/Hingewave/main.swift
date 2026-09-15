import AppKit
import Foundation
import HingewaveCore
import Metal

// Hingewave entry point.
//
//   Hingewave                          run the menu bar app
//   Hingewave --probe [sec]            print the lid angle for sec seconds (default 5)
//   Hingewave --render-check <dir>     render the golden set offscreen and report PSNR
//                [--core <coreDir>]    (core/ is found by walking up from the cwd otherwise)
//   Hingewave --simulate-close         scripted 120 to 0 to 120 lid sweep over the live desktop
//   Hingewave --demo                   the same sweep over a generated picture, no capture needed
//   Hingewave --preview <deg>          move to one lid angle and hold until the effect clears
//   ... --capturable                   let screenshots see the overlay (debugging only)

enum CLI {
    static func run(_ args: [String]) -> Int32 {
        if let i = args.firstIndex(of: "--probe") {
            let seconds = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 5 : 5
            return probe(seconds: seconds)
        }
        if let i = args.firstIndex(of: "--render-check") {
            guard args.indices.contains(i + 1) else {
                print("usage: Hingewave --render-check <outputDir> [--core <coreDir>]")
                return 2
            }
            let out = URL(fileURLWithPath: args[i + 1])
            var core: URL?
            if let c = args.firstIndex(of: "--core"), args.indices.contains(c + 1) {
                core = URL(fileURLWithPath: args[c + 1])
            }
            return RenderCheck.run(outputDir: out, coreDir: core)
        }
        let capturable = args.contains("--capturable")
        if args.contains("--simulate-close") {
            return runScripted(ScriptedAngleSource.closeAndReopen(), capturable: capturable, demo: false)
        }
        if args.contains("--demo") {
            return runScripted(ScriptedAngleSource.closeAndReopen(), capturable: capturable, demo: true)
        }
        if let i = args.firstIndex(of: "--preview"), args.indices.contains(i + 1), let deg = Double(args[i + 1]) {
            return runScripted(ScriptedAngleSource.preview(angle: deg), capturable: capturable, demo: false)
        }
        return runApp()
    }

    static func probe(seconds: Double) -> Int32 {
        guard let sensor = LidAngleSensor() else {
            print("No lid angle sensor found on this Mac.")
            return 1
        }
        print("sensor: \(sensor.resolution.label)")
        let deadline = Date().addingTimeInterval(seconds)
        var last: Double?
        while Date() < deadline {
            if let deg = sensor.readDegrees(), deg != last {
                print(String(format: "%.2f", deg))
                fflush(stdout)
                last = deg
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return 0
    }

    /// Runs the full overlay pipeline against a scripted angle source, then exits.
    static func runScripted(_ source: ScriptedAngleSource, capturable: Bool, demo: Bool) -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("no Metal device")
            return 2
        }
        if !demo && !ScreenStreamer.hasPermission() {
            print("Screen Recording permission is required. Requesting it now; grant it in System Settings, Privacy and Security, Screen Recording, then run again. Or run --demo, which needs no permission.")
            ScreenStreamer.requestPermission()
            return 3
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller: AppController
        do {
            controller = try AppController(device: device, source: source,
                                           reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                           capturable: capturable)
        } catch {
            print("renderer failed: \(error)")
            return 2
        }
        if demo, let screen = AppController.builtInScreen() ?? NSScreen.main {
            let scale = screen.backingScaleFactor
            controller.staticFrame = DemoPicture.makeTexture(device: device,
                                                             width: Int(screen.frame.width * scale),
                                                             height: Int(screen.frame.height * scale))
        }
        var lastPrinted = -1
        controller.onSample = { sample in
            let whole = Int(sample.angle.rounded())
            if whole != lastPrinted {
                print(String(format: "%5.1f deg  %-8@ tilt %5.1f progress %.2f", sample.angle, sample.output.state.rawValue as NSString, sample.output.tilt, sample.output.progress))
                lastPrinted = whole
            }
        }
        controller.onScriptFinished = {
            controller.stop()
            app.terminate(nil)
        }
        controller.start()
        app.run()
        return 0
    }

    /// The menu bar app.
    static func runApp() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Log.info("Hingewave starting")

        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.info("no Metal device")
            return 2
        }

        let sensor = LidAngleSensor()
        var controller: AppController?
        if let sensor {
            Log.info("lid sensor: \(sensor.resolution.label)")
            do {
                let c = try AppController(device: device, source: sensor,
                                          reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                let defaults = UserDefaults.standard
                if defaults.object(forKey: StatusItemController.followLidKey) != nil {
                    c.followLid = defaults.bool(forKey: StatusItemController.followLidKey)
                }
                controller = c
            } catch {
                Log.info("renderer failed: \(error)")
                return 2
            }
        } else {
            Log.info("no lid angle sensor")
        }

        let status = StatusItemController(controller: controller, sensorAvailable: sensor != nil)
        controller?.onSample = { sample in status.update(angle: sample.angle) }
        controller?.start()

        // Keep the status controller alive for the app's lifetime.
        objc_setAssociatedObject(app, "hingewave.status", status, .OBJC_ASSOCIATION_RETAIN)
        app.run()
        return 0
    }
}

exit(CLI.run(Array(CommandLine.arguments.dropFirst())))
