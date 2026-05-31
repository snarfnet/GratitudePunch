import Foundation
import Vision

// MARK: - Body Pose

struct BodyPose {
    var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        joints[joint]
    }

    func angle(a: VNHumanBodyPoseObservation.JointName,
               b: VNHumanBodyPoseObservation.JointName,
               c: VNHumanBodyPoseObservation.JointName) -> Double? {
        guard let pA = joints[a], let pB = joints[b], let pC = joints[c] else { return nil }
        let v1 = CGVector(dx: pA.x - pB.x, dy: pA.y - pB.y)
        let v2 = CGVector(dx: pC.x - pB.x, dy: pC.y - pB.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard mag1 > 0, mag2 > 0 else { return nil }
        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        return acos(cosAngle) * 180 / Double.pi
    }
}

// MARK: - Punch Quality

enum PunchQuality: String {
    case perfect = "完璧"
    case good = "良い"
    case ok = "まあまあ"
    case bad = "やり直し"

    var color: String {
        switch self {
        case .perfect: return "green"
        case .good: return "cyan"
        case .ok: return "yellow"
        case .bad: return "red"
        }
    }
}

// MARK: - Session Stats

struct SessionStats {
    var totalPunches: Int = 0
    var goodFormPunches: Int = 0
    var gratitudeCount: Int = 0
    var gratitudeWords: [String] = []
    var duration: TimeInterval = 0
    var punchesPerMinute: Double = 0

    // Form scores (rolling)
    var armExtension: Double = 0    // 腕の伸び
    var hikite: Double = 0          // 引き手
    var hipRotation: Double = 0     // 腰の回転
    var overallForm: Double { (armExtension + hikite + hipRotation) / 3 }

    var formRate: Double {
        guard totalPunches > 0 else { return 0 }
        return Double(goodFormPunches) / Double(totalPunches) * 100
    }

    // Daily tracking
    var dailyGoal: Int = 10000
    var dailyProgress: Double {
        min(Double(totalPunches) / Double(dailyGoal) * 100, 100)
    }
}

// MARK: - Gratitude Keywords

let gratitudeKeywords: [String] = [
    "ありがとう", "ありがと", "感謝", "かんしゃ",
    "おかげ", "お陰", "ありがたい", "ありがたき",
    "サンキュー", "さんきゅー",
    "thank", "thanks", "grateful", "appreciate",
]
