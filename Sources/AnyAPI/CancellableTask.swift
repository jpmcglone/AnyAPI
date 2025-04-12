import Alamofire
import Foundation

final class CancelableTask<T> {
  let request: DataRequest
  let task: Task<T, Error>

  init(request: DataRequest, task: Task<T, Error>) {
    self.request = request
    self.task = task
  }

  func cancel() {
    request.cancel()
    task.cancel()
  }
}
