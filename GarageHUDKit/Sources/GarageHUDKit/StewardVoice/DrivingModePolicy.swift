import Foundation

/// Represents the current context in which the user is interacting with
/// GarageHUD. Driving mode influences how verbose or constrained responses
/// should be. Enumerating modes explicitly makes policy decisions easier to
/// express and avoids magic numbers.
public enum DrivingMode: Codable, Hashable, Sendable {
    /// The vehicle is stationary and not being worked on. Responses can be
    /// more detailed since the user's attention is not split between driving
    /// and listening.
    case parked
    /// The vehicle is actively being driven. Responses should be concise
    /// and avoid requiring the user to look away from the road.
    case moving
    /// The vehicle is in the garage and the user is working on it. Hands
    /// may be occupied but the environment is stationary, allowing for
    /// moderately detailed responses.
    case working
    /// The user is reviewing data or history after the fact. Similar to
    /// `parked` but may warrant summarization across multiple sessions.
    case reviewing
}

/// Defines how responses should be adjusted based on driving mode. A policy
/// takes a parsed intent and a context and returns the appropriate reply.
/// Implementations can choose to shorten, defer, or elaborate responses
/// depending on safety considerations or user preference.
public protocol DrivingModePolicy {
    func response(for intent: StewardIntent, mode: DrivingMode) async -> String
}