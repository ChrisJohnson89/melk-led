//
//  ControlServer.swift
//  MelkLED
//
//  A tiny local HTTP endpoint (127.0.0.1:8765) so Hermes and the Python CLI
//  can drive the lights while the app remains the single BLE owner — one
//  device only accepts one connection, so we never want two processes
//  fighting over the link. Mirrors the routes of the Python FastAPI service
//  (melk_led/api.py) and ports the deterministic Hermes NLU (melk_led/nlu.py).
//
//  All I/O runs on a background queue; command execution hops to the main
//  actor (the controller's isolation) before touching Bluetooth.
//

import Foundation
import Network

final class ControlServer: ObservableObject {

    @Published private(set) var isRunning = false
    let port: UInt16 = 8765

    private let controller: MelkController
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.jetrails.MelkLED.server")

    init(controller: MelkController) {
        self.controller = controller
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Bind to loopback only — never expose control on the LAN.
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.isRunning = true
                    case .failed, .cancelled: self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(raw: buffer) {
                self.execute(request) { response in
                    connection.send(content: response.serialized(), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer) // need more bytes
        }
    }

    /// Route + run on the main actor, then hand the response back.
    private func execute(_ request: HTTPRequest, completion: @escaping (HTTPResponse) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                completion(self.route(request))
            }
        }
    }

    // MARK: - Routing (main actor)

    @MainActor
    private func route(_ req: HTTPRequest) -> HTTPResponse {
        switch (req.method, req.path) {
        case ("GET", "/health"):
            return .json(["ok": true, "devices": controller.devices.count])
        case ("GET", "/devices"):
            let list = controller.devices.map { d -> [String: Any] in
                ["name": d.name, "id": d.id.uuidString, "connected": d.isReady]
            }
            return .json(["devices": list])
        case ("GET", "/scenes"):
            return .json(["scenes": Scenes.all.map(\.name)])
        case ("POST", "/lights/on"):
            return fanOut(req, "on") { self.controller.setOn($0, true) }
        case ("POST", "/lights/off"):
            return fanOut(req, "off") { self.controller.setOn($0, false) }
        case ("POST", "/lights/color"):
            let r = req.int("r") ?? 255, g = req.int("g") ?? 255, b = req.int("b") ?? 255
            return fanOut(req, "color (\(r),\(g),\(b))") { self.controller.setColor($0, r: r, g: g, b: b) }
        case ("POST", "/lights/brightness"):
            let pct = max(0, min(100, req.int("percent") ?? 100))
            return fanOut(req, "brightness \(pct)%") { self.controller.setBrightness($0, percent: pct) }
        case ("POST", "/lights/white"):
            let warm = max(0, min(100, req.int("warm") ?? 50))
            return fanOut(req, "white \(warm)") { self.controller.setWhite($0, warmPercent: warm) }
        case ("POST", "/lights/scene"):
            guard let name = req.string("name"), let scene = Scenes.named(name) else {
                return .error("unknown scene", status: 400)
            }
            return fanOut(req, "scene \(scene.name)") { self.controller.apply(scene, to: $0) }
        case ("POST", "/lights/effect"):
            guard let id = resolveEffect(req.string("effect")) else {
                return .error("unknown effect", status: 400)
            }
            return fanOut(req, "effect \(id)") { self.controller.setEffect($0, id: id) }
        case ("POST", "/hermes"):
            guard let command = req.string("command") else { return .error("missing 'command'", status: 400) }
            return runHermes(command)
        case ("POST", "/flash"), ("GET", "/flash"):
            // Attention flash — e.g. an agent is waiting for the user to
            // approve something. GET is allowed so it is trivial to trigger.
            let r = req.int("r") ?? MelkController.alertColor.r
            let g = req.int("g") ?? MelkController.alertColor.g
            let b = req.int("b") ?? MelkController.alertColor.b
            let blinks = max(1, min(20, req.int("blinks") ?? 4))
            let target = req.string("target")
            let devices = controller.resolveTargets(target)
            guard !devices.isEmpty else {
                return .error("no devices matched target '\(target ?? "all")'", status: 404)
            }
            controller.flash(targets: devices, r: r, g: g, b: b, blinks: blinks)
            return .json(["ok": true, "action": "flash", "target": target ?? "all", "blinks": blinks])
        default:
            return .error("not found", status: 404)
        }
    }

    @MainActor
    private func fanOut(_ req: HTTPRequest, _ action: String, _ run: (MelkDevice) -> Void) -> HTTPResponse {
        let target = req.string("target")
        let devices = controller.resolveTargets(target)
        guard !devices.isEmpty else {
            return .error("no devices matched target '\(target ?? "all")'", status: 404)
        }
        devices.forEach(run)
        return .json(["ok": true, "action": action, "target": target ?? "all", "count": devices.count])
    }

    private func resolveEffect(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        if let id = Int(raw) { return id }
        let normalized = raw.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        return MelkProtocol.Effect.allCases.first {
            $0.label.lowercased().replacingOccurrences(of: " ", with: "") == normalized
        }?.rawValue
    }

    // MARK: - Hermes NLU (port of melk_led/nlu.py)

    private static let namedColors: [(String, (Int, Int, Int))] = [
        ("red", (255, 0, 0)), ("green", (0, 255, 0)), ("blue", (0, 0, 255)),
        ("yellow", (255, 255, 0)), ("orange", (255, 100, 0)), ("purple", (160, 0, 255)),
        ("pink", (255, 50, 150)), ("cyan", (0, 255, 255)), ("magenta", (255, 0, 255)),
    ]

    @MainActor
    private func runHermes(_ command: String) -> HTTPResponse {
        let text = command.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return .error("empty command", status: 400) }

        // Resolve target: longest device name that appears as a word, else all.
        let deviceNames = controller.devices.map { $0.name.lowercased() }
        var targetName: String? = nil
        for name in deviceNames.sorted(by: { $0.count > $1.count }) where matchesWord(name, in: text) {
            targetName = name
            break
        }
        let targets = controller.resolveTargets(targetName)
        let targetLabel = targetName ?? "all"

        func done(_ detail: String) -> HTTPResponse {
            .json(["ok": true, "target": targetLabel, "action": detail])
        }

        let reserved: Set<String> = ["warm", "cool", "cold", "white", "on", "off", "up", "out", "shut"]

        // Scenes: "<name> mode" or bare scene name.
        for scene in Scenes.all.sorted(by: { $0.name.count > $1.name.count }) {
            let n = scene.name
            if matchesRegex("\\b\(NSRegularExpression.escapedPattern(for: n))\\s+mode\\b", text) {
                targets.forEach { controller.apply(scene, to: $0) }
                return done("scene \(n)")
            }
            if reserved.contains(n) || deviceNames.contains(n) { continue }
            if matchesWord(n, in: text) {
                targets.forEach { controller.apply(scene, to: $0) }
                return done("scene \(n)")
            }
        }

        // Explicit color: "color 255 0 0".
        if let m = firstMatch("colou?r\\s+(\\d{1,3})\\s+(\\d{1,3})\\s+(\\d{1,3})", text), m.count == 4,
           let r = Int(m[1]), let g = Int(m[2]), let b = Int(m[3]) {
            targets.forEach { controller.setColor($0, r: r, g: g, b: b) }
            return done("color (\(r),\(g),\(b))")
        }

        // Named color ("white" is a temperature, handled below).
        for (name, rgb) in Self.namedColors where matchesWord(name, in: text) {
            targets.forEach { controller.setColor($0, r: rgb.0, g: rgb.1, b: rgb.2) }
            return done("color \(name)")
        }

        // Brightness: "brightness 40", "dim to 20", "40%".
        if let m = firstMatch("(?:brightness|dim(?:\\s+to)?|set\\s+to)\\s+(\\d{1,3})", text) ?? firstMatch("\\b(\\d{1,3})\\s*%", text),
           m.count >= 2, let pct = Int(m[1]) {
            let clamped = max(0, min(100, pct))
            targets.forEach { controller.setBrightness($0, percent: clamped) }
            return done("brightness \(clamped)%")
        }

        // White temperatures.
        if text.contains("warm") {
            targets.forEach { controller.setWhite($0, warmPercent: MelkProtocol.whiteWarm) }
            return done("white warm")
        }
        if text.contains("cool") || text.contains("cold") {
            targets.forEach { controller.setWhite($0, warmPercent: MelkProtocol.whiteCool) }
            return done("white cool")
        }
        if text.contains("white") {
            targets.forEach { controller.setWhite($0, warmPercent: MelkProtocol.whiteNeutral) }
            return done("white neutral")
        }

        // Power (check off before on).
        if matchesRegex("\\b(off|out|shut)\\b", text) {
            targets.forEach { controller.setOn($0, false) }
            return done("off")
        }
        if matchesRegex("\\b(on|up)\\b", text) {
            targets.forEach { controller.setOn($0, true) }
            return done("on")
        }

        return .error("could not understand '\(command)'", status: 422)
    }

    // MARK: - Regex helpers

    private func matchesWord(_ word: String, in text: String) -> Bool {
        matchesRegex("\\b\(NSRegularExpression.escapedPattern(for: word))\\b", text)
    }

    private func matchesRegex(_ pattern: String, _ text: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Returns [full, group1, group2, ...] for the first match, or nil.
    private func firstMatch(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        var groups: [String] = []
        for i in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}
