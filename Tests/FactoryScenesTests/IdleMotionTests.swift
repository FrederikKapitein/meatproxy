import Foundation
import Testing
@testable import FactoryScenes
import FactoryCore

/// Nobody on a floor stands still like a statue: what they do loops through poses the rig has frames for.
@Suite struct IdleMotionTests {
    @Test func everyLoopMovesAndUsesPosesTheFiguresHave() {
        let have = Set(Figure.specs.map { $0.pose })
        for state in [SessionState.working, .waiting, .stuck, .done] {
            for room in FloorRoom.allCases.map(\.rawValue) {
                for pose in ["idle", "type", "sit", "mug", "cheer"] {
                    for seated in [false, true] {
                        let loop = IdleMotion.loop(state: state, room: room, spotPose: pose, seated: seated, helper: false)
                        #expect(!loop.isEmpty)
                        #expect(loop.allSatisfy { have.contains($0.pose) && $0.seconds > 0 }, "\(state) \(room) \(pose)")
                        // standing, it is never one frozen pose
                        if !seated && !(state == .working && pose == "sit") {
                            #expect(Set(loop.map(\.pose)).count > 1, "\(state) \(room) \(pose) stands still")
                        }
                    }
                }
            }
        }
    }

    @Test func typingAlternatesAndWaitingRaisesAHand() {
        let typing = IdleMotion.loop(state: .working, room: "development", spotPose: "type", seated: true, helper: false)
        #expect(IdleMotion.frame(typing, t: 0.1).pose == "type")
        #expect(IdleMotion.frame(typing, t: 0.3).pose == "typeB")
        let waiting = IdleMotion.loop(state: .waiting, room: "needsYou", spotPose: "idle", seated: false, helper: false)
        #expect(IdleMotion.frame(waiting, t: 2.0) == (pose: "ask", mood: "wait"))
        let dozing = IdleMotion.loop(state: .done, room: "lounge", spotPose: "sit", seated: true, helper: false)
        #expect(IdleMotion.frame(dozing, t: 100).pose == "snooze")
        #expect(IdleMotion.frame([], t: 3) == (pose: "idle", mood: "calm"))
        // time wraps, also before zero
        #expect(IdleMotion.frame(waiting, t: -0.5).pose == "ask")
    }
}
