import Foundation

/// A component that accepts parsed intents and performs the associated action
/// within the application. On iOS this might dispatch to SwiftUI view
/// models; on macOS it could trigger menu commands. By decoupling routing
/// from recognition and parsing, the voice subsystem remains modular.
public protocol CommandRouter {
    /// Routes a parsed intent to the appropriate handler. Implementations
    /// should interpret the intent and either perform a side effect or update
    /// application state. Unrecognized intents can be ignored or surfaced as
    /// feedback to the user through a responder.
    func route(intent: StewardIntent)
}