import Foundation

/// The server's preferences for model selection, requested of the client during sampling.
///
/// Because LLMs can vary along multiple dimensions, choosing the "best" model is
/// rarely straightforward. Different models excel in different areas—some are
/// faster but less capable, others are more capable but more expensive, and so
/// on. This interface allows servers to express their priorities across multiple
/// dimensions to help clients make an appropriate selection for their use case.
///
/// These preferences are always advisory. The client MAY ignore them. It is also
/// up to the client to decide how to interpret these preferences and how to
/// balance them against other considerations.
public struct ModelPreferences: Codable, Sendable {

  // MARK: Lifecycle

  public init(
    costPriority: Double? = nil,
    hints: [ModelHint]? = nil,
    intelligencePriority: Double? = nil,
    speedPriority: Double? = nil)
  {
    self.costPriority = costPriority
    self.hints = hints
    self.intelligencePriority = intelligencePriority
    self.speedPriority = speedPriority
  }

  // MARK: Public

  /// How much to prioritize cost when selecting a model. A value of 0 means cost
  /// is not important, while a value of 1 means cost is the most important
  /// factor.
  public let costPriority: Double?

  /// Optional hints to use for model selection.
  ///
  /// If multiple hints are specified, the client MUST evaluate them in order
  /// (such that the first match is taken).
  ///
  /// The client SHOULD prioritize these hints over the numeric priorities, but
  /// MAY still use the priorities to select from ambiguous matches.
  public let hints: [ModelHint]?

  /// How much to prioritize intelligence and capabilities when selecting a
  /// model. A value of 0 means intelligence is not important, while a value of 1
  /// means intelligence is the most important factor.
  public let intelligencePriority: Double?

  /// How much to prioritize sampling speed (latency) when selecting a model. A
  /// value of 0 means speed is not important, while a value of 1 means speed is
  /// the most important factor.
  public let speedPriority: Double?

}
