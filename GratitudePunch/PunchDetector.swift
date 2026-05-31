import Foundation
import Vision
import QuartzCore

@Observable
final class PunchDetector {
    var stats = SessionStats()
    var lastQuality: PunchQuality?
    var isSessionActive = false
    var formFeedback = ""
    var formFeedbackEn = ""

    private var prevLeftWrist: CGPoint?
    private var prevRightWrist: CGPoint?
    private var lastPunchTime: CFTimeInterval = 0
    private var sessionStart: Date?

    // Form tracking (rolling samples)
    private var armExtSamples: [Double] = []
    private var hikiteSamples: [Double] = []
    private var rotationSamples: [Double] = []

    private let punchThreshold: Double = 0.05
    private let cooldownInterval: CFTimeInterval = 0.30

    func startSession() {
        stats = SessionStats()
        prevLeftWrist = nil
        prevRightWrist = nil
        lastPunchTime = 0
        sessionStart = Date()
        lastQuality = nil
        formFeedback = ""
        armExtSamples = []
        hikiteSamples = []
        rotationSamples = []
        isSessionActive = true
    }

    func stopSession() {
        isSessionActive = false
        if let start = sessionStart {
            stats.duration = Date().timeIntervalSince(start)
        }
    }

    func analyze(_ pose: BodyPose) {
        guard isSessionActive else { return }

        let now = CACurrentMediaTime()

        let lw = pose.point(.leftWrist)
        let rw = pose.point(.rightWrist)
        let le = pose.point(.leftElbow)
        let re = pose.point(.rightElbow)
        let ls = pose.point(.leftShoulder)
        let rs = pose.point(.rightShoulder)
        let lh = pose.point(.leftHip)
        let rh = pose.point(.rightHip)

        // Front camera: Vision's left = user's right
        if now - lastPunchTime >= cooldownInterval {
            // Check right hand punch (Vision left = user right for front cam)
            if let lw = lw, let plw = prevLeftWrist {
                let vel = hypot(lw.x - plw.x, lw.y - plw.y)
                if vel > punchThreshold {
                    let quality = evaluateSeikenForm(
                        punchWrist: lw, punchElbow: le, punchShoulder: ls,
                        pullWrist: rw, pullShoulder: rs,
                        leftHip: lh, rightHip: rh,
                        leftShoulder: ls, rightShoulder: rs
                    )
                    registerPunch(quality: quality, now: now)
                }
            }

            // Check left hand punch (Vision right = user left for front cam)
            if now - lastPunchTime >= cooldownInterval {
                if let rw = rw, let prw = prevRightWrist {
                    let vel = hypot(rw.x - prw.x, rw.y - prw.y)
                    if vel > punchThreshold {
                        let quality = evaluateSeikenForm(
                            punchWrist: rw, punchElbow: re, punchShoulder: rs,
                            pullWrist: lw, pullShoulder: ls,
                            leftHip: lh, rightHip: rh,
                            leftShoulder: ls, rightShoulder: rs
                        )
                        registerPunch(quality: quality, now: now)
                    }
                }
            }
        }

        prevLeftWrist = lw
        prevRightWrist = rw

        if let start = sessionStart {
            stats.duration = Date().timeIntervalSince(start)
            if stats.duration > 0 {
                stats.punchesPerMinute = Double(stats.totalPunches) / (stats.duration / 60)
            }
        }
    }

    // MARK: - Seiken (正拳突き) Form Evaluation

    private func evaluateSeikenForm(
        punchWrist: CGPoint, punchElbow: CGPoint?, punchShoulder: CGPoint?,
        pullWrist: CGPoint?, pullShoulder: CGPoint?,
        leftHip: CGPoint?, rightHip: CGPoint?,
        leftShoulder: CGPoint?, rightShoulder: CGPoint?
    ) -> PunchQuality {

        var score = 0.0
        var feedback: [String] = []

        // 1. Arm extension: shoulder → elbow → wrist should be nearly straight (> 150°)
        if let elbow = punchElbow, let shoulder = punchShoulder {
            let armLen = hypot(punchWrist.x - shoulder.x, punchWrist.y - shoulder.y)
            let upperArm = hypot(elbow.x - shoulder.x, elbow.y - shoulder.y)
            let foreArm = hypot(punchWrist.x - elbow.x, punchWrist.y - elbow.y)
            let fullExtent = upperArm + foreArm
            let extensionRatio = fullExtent > 0 ? armLen / fullExtent : 0

            let extScore = min(100.0, Double(extensionRatio) * 120.0)
            score += extScore * 0.4
            armExtSamples.append(extScore)

            if extensionRatio < 0.8 {
                feedback.append("腕をもっと伸ばす")
            }
        } else {
            score += 50 * 0.4
        }

        // 2. Hikite (引き手): pull hand should be near hip/waist level
        if let pullW = pullWrist, let pullS = pullShoulder {
            // Pull hand should be lower than shoulder and close to body
            let isLow = pullW.y > pullS.y
            let hikiteScore: Double
            if isLow {
                let dist = Double(pullW.y - pullS.y)
                hikiteScore = min(100.0, dist * 500.0)
            } else {
                let pullDown = Double(abs(pullS.y - pullW.y))
                hikiteScore = max(0.0, 30.0 - pullDown * 200.0)
                feedback.append("引き手を腰に引く")
            }
            score += hikiteScore * 0.3
            hikiteSamples.append(hikiteScore)
        } else {
            score += 50 * 0.3
        }

        // 3. Hip rotation: shoulder line vs hip line angle difference
        if let lh = leftHip, let rh = rightHip, let ls = leftShoulder, let rs = rightShoulder {
            let hipAngle = atan2(rh.y - lh.y, rh.x - lh.x)
            let shoulderAngle = atan2(rs.y - ls.y, rs.x - ls.x)
            let rotation = abs(hipAngle - shoulderAngle)
            let rotScore = min(100.0, Double(rotation) * 400.0)
            score += rotScore * 0.3
            rotationSamples.append(rotScore)

            if rotation < 0.05 {
                feedback.append("腰を回す")
            }
        } else {
            score += 50 * 0.3
        }

        // Update rolling form scores
        let window = 20
        stats.armExtension = avg(armExtSamples.suffix(window))
        stats.hikite = avg(hikiteSamples.suffix(window))
        stats.hipRotation = avg(rotationSamples.suffix(window))

        var feedbackEn: [String] = []
        if feedback.contains("腕をもっと伸ばす") { feedbackEn.append("Extend arm more") }
        if feedback.contains("引き手を腰に引く") { feedbackEn.append("Pull hand to hip") }
        if feedback.contains("腰を回す") { feedbackEn.append("Rotate hips") }
        formFeedback = feedback.isEmpty ? "良い型です" : feedback.joined(separator: " / ")
        formFeedbackEn = feedbackEn.isEmpty ? "Good form!" : feedbackEn.joined(separator: " / ")

        switch score {
        case 80...: return .perfect
        case 60..<80: return .good
        case 40..<60: return .ok
        default: return .bad
        }
    }

    private func registerPunch(quality: PunchQuality, now: CFTimeInterval) {
        lastPunchTime = now
        lastQuality = quality
        stats.totalPunches += 1

        if quality == .perfect || quality == .good {
            stats.goodFormPunches += 1
        }
    }

    private func avg(_ values: ArraySlice<Double>) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
