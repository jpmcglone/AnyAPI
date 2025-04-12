import Foundation

public struct RetryPolicy {
  public enum Strategy {
    case fixed(seconds: TimeInterval)
    case exponential(initial: TimeInterval, multiplier: Double = 2, max: TimeInterval? = nil)
    case immediate
  }

  public let maxAttempts: Int
  public let strategy: Strategy

  public init(maxAttempts: Int, strategy: Strategy = .immediate) {
    self.maxAttempts = maxAttempts
    self.strategy = strategy
  }

  func delay(for attempt: Int) -> TimeInterval {
    switch strategy {
    case .immediate: return 0
    case .fixed(let seconds): return seconds
    case .exponential(let initial, let multiplier, let max):
      let computed = initial * pow(multiplier, Double(attempt - 1))
      return min(computed, max ?? computed)
    }
  }
}
