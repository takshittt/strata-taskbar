import Foundation
import Testing
@testable import Strata

struct SnapActionTests {
    let landscape = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let portrait = CGRect(x: 0, y: 0, width: 900, height: 1200)
    let current = CGRect(x: 10, y: 10, width: 300, height: 200)

    @Test(arguments: [
        (SnapAction.leftHalf, CGRect(x: 0, y: 0, width: 600, height: 900)),
        (.rightHalf, CGRect(x: 600, y: 0, width: 600, height: 900)),
        (.topHalf, CGRect(x: 0, y: 0, width: 1200, height: 450)),
        (.bottomHalf, CGRect(x: 0, y: 450, width: 1200, height: 450)),
        (.topLeft, CGRect(x: 0, y: 0, width: 600, height: 450)),
        (.topRight, CGRect(x: 600, y: 0, width: 600, height: 450)),
        (.bottomLeft, CGRect(x: 0, y: 450, width: 600, height: 450)),
        (.bottomRight, CGRect(x: 600, y: 450, width: 600, height: 450)),
        (.firstThird, CGRect(x: 0, y: 0, width: 400, height: 900)),
        (.centerThird, CGRect(x: 400, y: 0, width: 400, height: 900)),
        (.lastThird, CGRect(x: 800, y: 0, width: 400, height: 900)),
        (.firstTwoThirds, CGRect(x: 0, y: 0, width: 800, height: 900)),
        (.lastTwoThirds, CGRect(x: 400, y: 0, width: 800, height: 900)),
        (.maximize, CGRect(x: 0, y: 0, width: 1200, height: 900)),
        (.center, CGRect(x: 450, y: 350, width: 300, height: 200)),
    ])
    func landscapeFrames(action: SnapAction, expected: CGRect) {
        #expect(action.frame(in: landscape, current: current, gap: 0) == expected)
    }

    @Test(arguments: [
        (SnapAction.leftHalf, CGRect(x: 0, y: 0, width: 450, height: 1200)),
        (.bottomHalf, CGRect(x: 0, y: 600, width: 900, height: 600)),
        (.topRight, CGRect(x: 450, y: 0, width: 450, height: 600)),
        (.firstThird, CGRect(x: 0, y: 0, width: 900, height: 400)),
        (.centerThird, CGRect(x: 0, y: 400, width: 900, height: 400)),
        (.lastThird, CGRect(x: 0, y: 800, width: 900, height: 400)),
        (.firstTwoThirds, CGRect(x: 0, y: 0, width: 900, height: 800)),
        (.lastTwoThirds, CGRect(x: 0, y: 400, width: 900, height: 800)),
        (.maximize, CGRect(x: 0, y: 0, width: 900, height: 1200)),
    ])
    func portraitThirdsRunAlongTheLongEdge(action: SnapAction, expected: CGRect) {
        #expect(action.frame(in: portrait, current: current, gap: 0) == expected)
    }

    @Test(arguments: [SnapAction.restore, .previousDisplay, .nextDisplay])
    func nonRegionActionsHaveNoFrame(action: SnapAction) {
        #expect(action.frame(in: landscape, current: current, gap: 0) == nil)
    }

    @Test func framesFollowTheAreaOrigin() {
        let area = CGRect(x: 100, y: 25, width: 1200, height: 900)
        #expect(SnapAction.maximize.frame(in: area, current: current, gap: 0) == area)
        #expect(SnapAction.rightHalf.frame(in: area, current: current, gap: 0) == CGRect(x: 700, y: 25, width: 600, height: 900))
    }

    @Test func gapIsEvenAtEdgesAndBetweenWindows() {
        let left = SnapAction.leftHalf.frame(in: landscape, current: current, gap: 10)!
        let right = SnapAction.rightHalf.frame(in: landscape, current: current, gap: 10)!
        #expect(left == CGRect(x: 10, y: 10, width: 585, height: 880))
        #expect(right == CGRect(x: 605, y: 10, width: 585, height: 880))
        #expect(right.minX - left.maxX == 10)
        #expect(landscape.maxX - right.maxX == 10)

        let thirds = [SnapAction.firstThird, .centerThird, .lastThird].map { $0.frame(in: landscape, current: current, gap: 12)! }
        #expect(thirds[0].minX == 12)
        #expect(thirds[1].minX - thirds[0].maxX == 12)
        #expect(thirds[2].minX - thirds[1].maxX == 12)
        #expect(landscape.maxX - thirds[2].maxX == 12)
    }

    @Test func centerClampsAWindowLargerThanTheArea() {
        let big = CGRect(x: 0, y: 0, width: 2000, height: 300)
        #expect(SnapAction.center.frame(in: landscape, current: big, gap: 0) == CGRect(x: 0, y: 300, width: 1200, height: 300))
    }

    @Test func defaultShortcutsAreUnique() {
        let shortcuts = SnapAction.allCases.map(\.defaultShortcut)
        #expect(Set(shortcuts).count == SnapAction.allCases.count)
    }

    @Test func menuGroupsCoverEveryActionOnce() {
        let grouped = SnapAction.menuGroups.flatMap { $0 }
        #expect(grouped.count == SnapAction.allCases.count)
        #expect(Set(grouped) == Set(SnapAction.allCases))
    }
}
