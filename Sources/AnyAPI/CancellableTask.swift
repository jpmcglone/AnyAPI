import Alamofire
import Foundation

public final class CancelableTask<T> {
  public let request: DataRequest
  public let task: Task<T, Error>

  public init(request: DataRequest, task: Task<T, Error>) {
    self.request = request
    self.task = task
  }

  public func cancel() {
    request.cancel()
    task.cancel()
  }
}
