import Foundation

/// What the owner is asking about. Kept intentionally small — a handful of high-value
/// topics we can answer *from recorded memory with confidence*, per the Constitution's
/// "observe first, advise second."
public enum StewardTopic: Equatable, Sendable {
    case greeting
    case power
    case investment
    case efficiency
    case observations
    case activity
    case log
    case help
    case unknown
}

/// A Steward answer: evidence-first text plus, when the answer rests on evidence of a known
/// strength, the band behind it — never a fabricated percentage.
public struct StewardReply: Equatable, Sendable {
    public let text: String
    public let confidence: ConfidenceBand?
    public init(text: String, confidence: ConfidenceBand? = nil) {
        self.text = text
        self.confidence = confidence
    }
}

/// The text-first conversational core. Pure and synchronous so it is fully testable;
/// speech capture and TTS wrap around it later without changing this logic.
///
/// Interaction model (Constitution): "Steward…" / "Go ahead." — conversation, not commands.
public enum StewardConversation {

    // MARK: Topic detection

    public static func topic(for utterance: String) -> StewardTopic {
        let s = utterance.lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { s.contains($0) } }

        if s.trimmingCharacters(in: .whitespaces).isEmpty { return .unknown }
        if has(["help", "what can you", "what do you do"]) { return .help }
        if has(["start a log", "log ", "record ", "capture"]) { return .log }
        if has(["per hp", "cost per", "per horsepower", "efficien", "worth it", "value"]) { return .efficiency }
        if has(["spend", "spent", "invest", "how much have i", "budget", "money", "cost so far"]) { return .investment }
        if has(["power", "horsepower", "whp", " hp", "torque", "how fast"]) { return .power }
        if has(["watch", "concern", "worry", "wrong", "look", "how's", "how is", "status", "anything", "should i", "next"]) { return .observations }
        if has(["last", "when did", "recent", "quiet", "how long"]) { return .activity }
        if has(["steward", "hey", "hello", "hi ", "good morning", "you there"]) { return .greeting }
        return .unknown
    }

    // MARK: Reply

    public static func reply(to utterance: String, vehicle: Vehicle, mode: DrivingMode = .parked) -> StewardReply {
        let full = answer(topic(for: utterance), vehicle: vehicle)
        return StewardReply(text: shape(full.text, mode: mode), confidence: full.confidence)
    }

    private static func answer(_ topic: StewardTopic, vehicle: Vehicle) -> StewardReply {
        switch topic {
        case .greeting:
            return StewardReply(text: "Go ahead.")

        case .power:
            if let dyno = vehicle.latestMeasuredDyno, let hp = dyno.wheelHorsepower {
                return StewardReply(
                    text: "I observed \(Int(hp)) wheel-hp — measured on the dyno \(short(dyno.date)).",
                    confidence: .strong)
            }
            if let factory = vehicle.factoryHorsepower {
                return StewardReply(
                    text: "The factory rating is \(Int(factory)) hp (\(vehicle.factoryPowerBasis.describes)). No dyno is logged yet, so treat that as an estimate.",
                    confidence: .weak)
            }
            return StewardReply(text: "No horsepower is on record yet — log a dyno pull and I can speak to it.")

        case .investment:
            guard vehicle.totalInvested > 0 else {
                return StewardReply(text: "No spend is documented yet.")
            }
            let word = vehicle.investmentIsLiveFromParts ? "logged" : "documented"
            return StewardReply(
                text: "You've \(word) \(dollars(vehicle.totalInvested)) invested so far.")

        case .efficiency:
            if let costPerHp = vehicle.costPerHorsepowerGained, let gained = vehicle.horsepowerGainedOverStock {
                return StewardReply(
                    text: "Roughly \(dollars(costPerHp)) per wheel-hp gained "
                        + "— about \(Int(gained)) whp over an estimated stock wheel baseline, for \(dollars(vehicle.totalInvested)). "
                        + "A wheel-to-wheel estimate using typical \(vehicle.drivetrain.label) driveline loss, not dyno-corrected.",
                    confidence: .moderate)
            }
            return StewardReply(text: "I need a factory baseline, a dyno pull, and a documented total before I can size that up.")

        case .observations:
            let obs = Steward.observe(vehicle)
            guard !obs.isEmpty else { return StewardReply(text: "Nothing stands out right now.") }
            let lead = obs.prefix(2).map { "\($0.statement) (\($0.confidence.spokenPhrase))" }.joined(separator: " ")
            let count = obs.count == 1 ? "One thing stands out." : "\(obs.count) things stand out."
            return StewardReply(text: "\(count) \(lead)", confidence: obs.first?.confidence)

        case .activity:
            if let last = vehicle.lastActivityDate {
                let days = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
                return StewardReply(text: "Last logged activity was \(short(last)) — \(days) days ago.")
            }
            return StewardReply(text: "No activity is logged yet.")

        case .log:
            return StewardReply(text: "I can't log records by voice yet — add them on the Performance and Timeline tabs.")

        case .help:
            return StewardReply(text: "Ask me about power, spend, efficiency, or what to watch — by voice or text.")

        case .unknown:
            return StewardReply(text: "I didn't catch that. Try: what's my power, what did I spend, or what should I watch?")
        }
    }

    // MARK: Driving-mode shaping (the safety-critical piece per ARCHITECTURE)

    /// While the vehicle is moving, answers must get shorter and stop demanding attention:
    /// first sentence only. Everywhere else, the full answer stands.
    static func shape(_ text: String, mode: DrivingMode) -> String {
        guard mode == .moving else { return text }
        return StewardBriefingBuilder.firstSentence(text)
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    private static func dollars(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
}

// MARK: - Boundary conformances (honor the StewardVoice architecture)

/// A minimal keyword parser conforming to the voice `IntentParser` boundary.
public struct KeywordIntentParser: IntentParser {
    public init() {}
    public func parse(_ utterance: String) -> StewardIntent { StewardIntent(raw: utterance) }
}

/// A `VoiceResponder` that answers from a specific vehicle in a given driving mode.
public struct StewardResponder: VoiceResponder {
    public var vehicle: Vehicle
    public var mode: DrivingMode
    public init(vehicle: Vehicle, mode: DrivingMode = .parked) {
        self.vehicle = vehicle
        self.mode = mode
    }
    public func respond(to intent: StewardIntent) async -> String {
        StewardConversation.reply(to: intent.raw, vehicle: vehicle, mode: mode).text
    }
}
