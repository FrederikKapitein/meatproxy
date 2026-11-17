import Foundation
import FactoryCore

/// What someone who is not walking is doing, as a short loop of poses, so nobody on a floor stands still like a statue:
/// at a desk they type, in Research they read, in Planning they point at the board, waiting they raise a hand, done
/// they sip a coffee, doze off in a chair or cheer at a game in the lounge.
public enum IdleMotion {
    public typealias Step = (pose: String, mood: String, seconds: Double)

    /// The loop for a state, a room and the pose of the spot they hold (type, sit, mug, idle, …).
    public static func loop(state: SessionState, room: String, spotPose: String, seated: Bool, helper: Bool) -> [Step] {
        switch state {
        case .waiting:
            return seated ? [("sit", "calm", 3)] : [("idle", "wait", 1.6), ("ask", "wait", 1.3)]
        case .stuck:
            return seated ? [("sit", "calm", 3)] : [("stuck", "stuck", 2.2), ("idle", "wait", 0.9)]
        case .done:
            if seated { return [("snooze", "tired", 6)] }
            if spotPose == "mug" { return [("mug", "tired", 2.6), ("idle", "tired", 1.8)] }
            if room == FloorRoom.lounge.rawValue { return [("idle", "tired", 2.4), ("cheer", "happy", 0.5), ("idle", "calm", 0.9), ("mug", "tired", 2.2)] }
            return [("idle", "tired", 3), ("mug", "tired", 2)]
        case .working:
            if spotPose == "type" {
                // bursts of typing with a pause to read the screen
                return Array(repeating: [("type", "focus", 0.2), ("typeB", "focus", 0.2)] as [Step], count: 6).flatMap { $0 } + [("type", "focus", 1.3)]
            }
            if seated || spotPose == "sit" { return [("sit", "calm", 3)] }
            if spotPose == "mug" { return [("mug", "tired", 2.4), ("idle", "calm", 1.6)] }
            if spotPose == "cheer" || spotPose == "wave" { return [(spotPose, "happy", 1.1), ("idle", "calm", 1.2)] }
            if helper { return [("idle", "calm", 1.4), ("read", "calm", 1.8), ("point", "calm", 1.0)] }
            switch FloorRoom(rawValue: room) {
            case .research?: return [("read", "calm", 3.2), ("idle", "calm", 0.9), ("read", "calm", 2.2)]
            case .planning?: return [("point", "calm", 1.4), ("idle", "calm", 1.1), ("read", "calm", 1.6)]
            case .testing?: return [("read", "calm", 2.0), ("point", "calm", 1.0), ("idle", "calm", 1.0)]
            default: return [("point", "calm", 1.2), ("idle", "calm", 1.6)]
            }
        }
    }

    /// The pose at time `t` (seconds) along the loop.
    public static func frame(_ loop: [Step], t: Double) -> (pose: String, mood: String) {
        guard let first = loop.first else { return ("idle", "calm") }
        let total = loop.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return (first.pose, first.mood) }
        var x = t.truncatingRemainder(dividingBy: total)
        if x < 0 { x += total }
        for s in loop { if x < s.seconds { return (s.pose, s.mood) }; x -= s.seconds }
        return (first.pose, first.mood)
    }
}
