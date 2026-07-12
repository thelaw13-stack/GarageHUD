import Foundation

/// The ELM327 bring-up sequence as an explicit, pure state machine. Real adapters are
/// command-response serial devices: each command must be sent, then acknowledged (a
/// prompt-terminated reply) or timed out and retried — never pipelined and assumed. This
/// type owns that sequencing so the transport just feeds it completed replies/timeouts and
/// does what it says. Being pure, every transition is unit-tested without hardware.
public struct ELM327Handshake: Equatable, Sendable {

    public enum Step: Equatable, Sendable {
        case reset               // ATZ — may take a beat; adapter answers when ready
        case configure(Int)      // ATE0, ATL0, ATH0, ATSP0…
        case done
    }

    /// A completed reply line (prompt already stripped) or a timeout for the in-flight command.
    public enum Event: Equatable, Sendable {
        case reply(String)
        case timeout
    }

    /// What the transport should do next.
    public enum Action: Equatable, Sendable {
        case send(String)   // transmit this command and arm a timeout
        case ready          // handshake complete — begin polling
        case failed         // give up (retries exhausted) — degrade/reconnect
    }

    public let resetCommand: String
    public let configCommands: [String]
    public let maxAttempts: Int
    /// When true, the `ATZ` reply must look like an ELM327 (its version banner contains
    /// `identityToken`) — otherwise the device is rejected as not an ELM327-compatible adapter.
    public let verifyIdentity: Bool
    public let identityToken: String

    public private(set) var step: Step
    public private(set) var attempts: Int

    public init(resetCommand: String = "ATZ",
                configCommands: [String] = ["ATE0", "ATL0", "ATH0", "ATSP0"],
                maxAttempts: Int = 3,
                verifyIdentity: Bool = true,
                identityToken: String = "ELM") {
        self.resetCommand = resetCommand
        self.configCommands = configCommands
        self.maxAttempts = maxAttempts
        self.verifyIdentity = verifyIdentity
        self.identityToken = identityToken
        self.step = .reset
        self.attempts = 0
    }

    /// The command for the current step (nil once done).
    public var currentCommand: String? {
        switch step {
        case .reset: return resetCommand
        case .configure(let i): return i < configCommands.count ? configCommands[i] : nil
        case .done: return nil
        }
    }

    /// The first command to transmit when the link comes up.
    public var openingCommand: String { resetCommand }

    /// ELM327 error / non-ready markers. `SEARCHING` and `BUS INIT` are progress, not errors,
    /// and are ignored here (they appear on PID polls, not on these AT commands).
    public static func isError(_ line: String) -> Bool {
        let u = line.uppercased()
        for token in ["?", "ERROR", "UNABLE", "NO DATA", "STOPPED"] where u.contains(token) { return true }
        return false
    }

    /// Advance on a completed reply or a timeout. Mutates state and returns the next action.
    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .reply(let line):
            if Self.isError(line) { return retryOrFail() }
            // The reset reply must identify an ELM327. A device that answers cleanly but isn't
            // one is rejected outright — retrying can't change what it is.
            if case .reset = step, verifyIdentity,
               !line.uppercased().contains(identityToken.uppercased()) {
                return .failed
            }
            return advance()
        case .timeout:
            return retryOrFail()
        }
    }

    private mutating func advance() -> Action {
        attempts = 0
        switch step {
        case .reset:
            step = configCommands.isEmpty ? .done : .configure(0)
        case .configure(let i):
            let next = i + 1
            step = next < configCommands.count ? .configure(next) : .done
        case .done:
            break
        }
        if let cmd = currentCommand { return .send(cmd) }
        return .ready
    }

    private mutating func retryOrFail() -> Action {
        attempts += 1
        if attempts >= maxAttempts { return .failed }
        if let cmd = currentCommand { return .send(cmd) }
        return .ready
    }
}
