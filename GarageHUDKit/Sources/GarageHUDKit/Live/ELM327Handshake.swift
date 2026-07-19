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
        /// 0100 — the protocol bind. With ATSP0 (auto), the FIRST OBD query triggers the
        /// protocol search, which takes seconds on a CAN car. Binding here — inside the
        /// handshake, where the long-timeout retry logic lives — is what standard ELM bring-up
        /// does, and skipping it is exactly what stranded the first driveway session (W-052):
        /// polling began with a 1s timeout, the search outlived it, and every late reply was
        /// discarded while the next poll aborted the search.
        case bind
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
    /// The protocol-bind query sent after configuration — a real OBD request whose reply proves
    /// the VEHICLE (not just the adapter) is answering. "0100" (supported PIDs) is the standard.
    public let bindCommand: String
    public let maxAttempts: Int
    /// When true, the `ATZ` reply must look like a supported ELM/STN command processor. Genuine
    /// OBDLink hardware commonly identifies as OBDLink or STN rather than containing "ELM".
    public let verifyIdentity: Bool
    public let identityTokens: [String]

    public private(set) var step: Step
    public private(set) var attempts: Int

    public init(resetCommand: String = "ATZ",
                configCommands: [String] = ["ATE0", "ATL0", "ATH0", "ATSP0"],
                bindCommand: String = "0100",
                maxAttempts: Int = 3,
                verifyIdentity: Bool = true,
                identityTokens: [String] = ["ELM", "OBDLINK", "STN"]) {
        self.resetCommand = resetCommand
        self.configCommands = configCommands
        self.bindCommand = bindCommand
        self.maxAttempts = maxAttempts
        self.verifyIdentity = verifyIdentity
        self.identityTokens = identityTokens
        self.step = .reset
        self.attempts = 0
    }

    /// The command for the current step (nil once done).
    public var currentCommand: String? {
        switch step {
        case .reset: return resetCommand
        case .configure(let i): return i < configCommands.count ? configCommands[i] : nil
        case .bind: return bindCommand
        case .done: return nil
        }
    }

    /// True while the vehicle-protocol bind is in flight — the transport gives this step a long
    /// timeout (the auto protocol search takes seconds) and a distinct failure message ("the
    /// vehicle didn't answer" is not "the adapter is broken").
    public var isBinding: Bool { step == .bind }

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
            // The bind step succeeds only on a real OBD answer ("41 00 …"), which may arrive in
            // the same prompt-chunk as "SEARCHING…". Errors (UNABLE TO CONNECT / NO DATA /
            // STOPPED) mean the adapter is fine but the VEHICLE didn't answer — retry, then fail
            // with the bind context so the UI can say "ignition on?" instead of blaming hardware.
            if case .bind = step {
                let compact = line.uppercased().replacingOccurrences(of: " ", with: "")
                if compact.contains("41" + bindSuffix) { return advance() }
                return retryOrFail()
            }
            if Self.isError(line) { return retryOrFail() }
            // The reset reply must identify an ELM327. A device that answers cleanly but isn't
            // one is rejected outright — retrying can't change what it is.
            if case .reset = step, verifyIdentity {
                let upper = line.uppercased()
                guard identityTokens.contains(where: { upper.contains($0.uppercased()) }) else {
                    return .failed
                }
            }
            return advance()
        case .timeout:
            return retryOrFail()
        }
    }

    /// "0100" → the reply's mode+PID echo is "4100…".
    private var bindSuffix: String { String(bindCommand.uppercased().replacingOccurrences(of: " ", with: "").dropFirst(2)) }

    private mutating func advance() -> Action {
        attempts = 0
        switch step {
        case .reset:
            step = configCommands.isEmpty ? .bind : .configure(0)
        case .configure(let i):
            let next = i + 1
            step = next < configCommands.count ? .configure(next) : .bind
        case .bind:
            step = .done
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
