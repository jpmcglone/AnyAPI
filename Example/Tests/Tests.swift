@testable import AnyAPI

import Quick
import Nimble

class TestsSpec: QuickSpec {
  override func spec() {
    describe("these will pass") {
      it("can do maths") {
        expect(23).to(equal(23))
      }

      it("can read") {
        expect("🐮").to(equal("🐮"))
      }

      it("will eventually pass") {
        var time = "passing"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          time = "done"
        }

        expect(time).toEventually(equal("done"))
      }
    }
  }
}
