import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @State private var camera = CameraManager()
    @State private var detector = PunchDetector()
    @State private var speech = SpeechListener()
    @State private var showResults = false

    private let isEn = Locale.preferredLanguages.first?.hasPrefix("en") == true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if detector.isSessionActive {
                sessionView
            } else if showResults {
                resultsView
            } else {
                startView
            }
        }
        .statusBarHidden(detector.isSessionActive)
        .onAppear {
            camera.onPose = { pose in
                detector.analyze(pose)
            }
            camera.start()
            speech.requestPermission { _ in }
        }
    }

    // MARK: - Start Screen

    private var startView: some View {
        VStack(spacing: 30) {
            Spacer()

            Text("👊")
                .font(.system(size: 100))

            Text(isEn ? "Gratitude Punch" : "感謝の正拳突き")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text(isEn ? "10,000 Punches a Day" : "一日一万回")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)

            Spacer()

            VStack(spacing: 8) {
                Text(isEn ? "Check your punch form" : "正拳突きの型をチェック")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Text(isEn ? "Say words of gratitude" : "感謝の言葉を声に出そう")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            Button {
                detector.startSession()
                speech.reset()
                speech.start()
            } label: {
                Text(isEn ? "START TRAINING" : "修行開始")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Session View

    private var sessionView: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Skeleton
            if let pose = camera.currentPose {
                SkeletonOverlay(pose: pose)
                    .ignoresSafeArea()
            }

            VStack {
                // Top HUD
                HStack(alignment: .top) {
                    // Punch counter
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(detector.stats.totalPunches)")
                            .font(.system(size: 60, weight: .black, design: .monospaced))
                            .foregroundColor(.orange)
                        Text(isEn ? "PUNCHES" : "正拳突き")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.7))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        // Recording indicator
                        if speech.isListening {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)
                                Text(isEn ? "REC" : "録音中")
                                    .font(.system(size: 12, weight: .black, design: .monospaced))
                                    .foregroundColor(.red)
                            }
                        }

                        // Time
                        Text(durationText)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))

                        // PPM
                        Text(String(format: "%.0f /分", detector.stats.punchesPerMinute))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.cyan)

                        // Gratitude count
                        HStack(spacing: 4) {
                            Text("🙏")
                                .font(.system(size: 14))
                            Text("\(speech.gratitudeCount)")
                                .font(.system(size: 18, weight: .black, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(.black.opacity(0.6))

                Spacer()

                // Punch quality flash
                if let quality = detector.lastQuality {
                    punchFlash(quality)
                        .transition(.scale.combined(with: .opacity))
                        .id(detector.stats.totalPunches)
                }

                // Form feedback
                if !detector.formFeedback.isEmpty {
                    Text(isEn ? detector.formFeedbackEn : detector.formFeedback)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6))
                        .cornerRadius(8)
                }

                // Gratitude heard flash
                if !speech.lastHeardWord.isEmpty {
                    Text("🙏 \(speech.lastHeardWord)!!")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.15))
                        .cornerRadius(10)
                        .id("gratitude_\(speech.gratitudeCount)")
                        .transition(.scale)
                }

                Spacer()

                // Form scores (right side)
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        formRow(isEn ? "Extend" : "腕の伸び", detector.stats.armExtension)
                        formRow(isEn ? "Pull" : "引き手", detector.stats.hikite)
                        formRow(isEn ? "Hip" : "腰回転", detector.stats.hipRotation)
                    }
                    .padding(10)
                    .background(.black.opacity(0.6))
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)

                // Progress bar toward 10,000
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * min(detector.stats.dailyProgress / 100, 1))
                        }
                    }
                    .frame(height: 8)

                    Text("\(detector.stats.totalPunches) / \(detector.stats.dailyGoal)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

                // Stop button
                Button {
                    detector.stopSession()
                    speech.stop()
                    detector.stats.gratitudeCount = speech.gratitudeCount
                    detector.stats.gratitudeWords = speech.gratitudeWords
                    showResults = true
                } label: {
                    Text(isEn ? "STOP" : "終了")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 50)
                        .padding(.vertical, 16)
                        .background(.red.opacity(0.8))
                        .cornerRadius(14)
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func punchFlash(_ quality: PunchQuality) -> some View {
        Text(quality.rawValue)
            .font(.system(size: 36, weight: .black, design: .rounded))
            .foregroundColor(qualityColor(quality))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.black.opacity(0.5))
            .cornerRadius(12)
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(isEn ? "SESSION RESULTS" : "修行結果")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.orange)
                    .padding(.top, 60)

                VStack(spacing: 16) {
                    resultCard(isEn ? "👊 Punches" : "👊 正拳突き", "\(detector.stats.totalPunches)")
                    resultCard(isEn ? "✅ Good Form" : "✅ 正しい型", "\(detector.stats.goodFormPunches) (\(String(format: "%.0f%%", detector.stats.formRate)))")
                    resultCard(isEn ? "🙏 Gratitude" : "🙏 感謝の言葉", "\(detector.stats.gratitudeCount)")
                    resultCard(isEn ? "⏱ Time" : "⏱ 時間", durationText)
                    resultCard(isEn ? "⚡ Pace" : "⚡ ペース", String(format: "%.0f /min", detector.stats.punchesPerMinute))
                }
                .padding(.horizontal, 20)

                // Form breakdown
                VStack(spacing: 12) {
                    Text(isEn ? "FORM RATING" : "フォーム評価")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)

                    ratingBar(isEn ? "Extension" : "腕の伸び", detector.stats.armExtension)
                    ratingBar(isEn ? "Pull Hand" : "引き手", detector.stats.hikite)
                    ratingBar(isEn ? "Hip Rotation" : "腰の回転", detector.stats.hipRotation)
                }
                .padding(20)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .padding(.horizontal, 20)

                // Gratitude words heard
                if !detector.stats.gratitudeWords.isEmpty {
                    VStack(spacing: 8) {
                        Text(isEn ? "Gratitude Words Heard" : "聞こえた感謝の言葉")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)

                        ForEach(detector.stats.gratitudeWords, id: \.self) { word in
                            Text("「\(word)」")
                                .font(.system(size: 18, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(20)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                }

                // Motivation message
                motivationMessage

                // Restart
                Button {
                    showResults = false
                } label: {
                    Text(isEn ? "TRAIN AGAIN" : "もう一度修行する")
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }

    private func resultCard(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    private func ratingBar(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(scoreColor(value))
                        .frame(width: geo.size.width * min(value / 100, 1))
                }
            }
            .frame(height: 10)

            Text(String(format: "%.0f", value))
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(scoreColor(value))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var motivationMessage: some View {
        let total = detector.stats.totalPunches
        let gratitude = detector.stats.gratitudeCount
        let msg: String
        if total >= 10000 {
            msg = isEn ? "10,000 reached! One step closer to mastery!" : "一万回達成！ネテロ会長に一歩近づいた！"
        } else if total >= 5000 {
            msg = isEn ? "Halfway there! Keep going!" : "半分到達！この調子で続けろ！"
        } else if total >= 1000 {
            msg = isEn ? "1,000 punches! Just getting started!" : "千回突破！まだまだこれから！"
        } else if gratitude > total {
            msg = isEn ? "Your gratitude overflows!" : "感謝の気持ちが溢れている！"
        } else if gratitude == 0 && total > 0 {
            msg = isEn ? "Good punches, but where's the gratitude?" : "突きは出てるけど、感謝の気持ちは？"
        } else {
            msg = isEn ? "A journey of 10,000 begins with one punch." : "千里の道も一歩から。明日も修行だ。"
        }
        return Text(msg)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(.orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
    }

    // MARK: - Helpers

    private func formRow(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            Text(String(format: "%.0f", value))
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(scoreColor(value))
        }
    }

    private var durationText: String {
        let mins = Int(detector.stats.duration) / 60
        let secs = Int(detector.stats.duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func qualityColor(_ q: PunchQuality) -> Color {
        switch q {
        case .perfect: return .green
        case .good: return .cyan
        case .ok: return .yellow
        case .bad: return .red
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        default: return .red
        }
    }
}

// MARK: - Skeleton Overlay

struct SkeletonOverlay: View {
    let pose: BodyPose

    private let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
    ]

    var body: some View {
        Canvas { context, size in
            for (from, to) in connections {
                guard let p1 = pose.point(from), let p2 = pose.point(to) else { continue }
                let sp1 = CGPoint(x: p1.x * size.width, y: p1.y * size.height)
                let sp2 = CGPoint(x: p2.x * size.width, y: p2.y * size.height)
                var path = Path()
                path.move(to: sp1)
                path.addLine(to: sp2)
                context.stroke(path, with: .color(.orange.opacity(0.7)), lineWidth: 3)
            }
            for (_, point) in pose.joints {
                let sp = CGPoint(x: point.x * size.width, y: point.y * size.height)
                let rect = CGRect(x: sp.x - 5, y: sp.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: rect), with: .color(.orange))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}
