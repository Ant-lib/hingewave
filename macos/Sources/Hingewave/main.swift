import Foundation
import HingewaveCore

// Hingewave entry point.
//
//   Hingewave                          run the menu bar app (added in a later task)
//   Hingewave --probe [sec]            print the lid angle for sec seconds (default 5)
//   Hingewave --render-check <dir>     render the golden set offscreen and report PSNR
//                [--core <coreDir>]    (core/ is found by walking up from the cwd otherwise)

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
        print("Hingewave \(EffectConfig.defaults.laptop.startAngle)")
        return 0
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
}

exit(CLI.run(Array(CommandLine.arguments.dropFirst())))
