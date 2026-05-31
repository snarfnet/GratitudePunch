import AVFoundation
import Vision
import UIKit

@Observable
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    var currentPose: BodyPose?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.pose.queue")
    private let confidenceThreshold: Float = 0.1

    var onPose: ((BodyPose) -> Void)?

    func start() {
        guard !session.isRunning else { return }
        queue.async { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = true
        }

        session.commitConfiguration()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest { [weak self] request, _ in
            guard let self = self,
                  let results = request.results as? [VNHumanBodyPoseObservation],
                  let observation = results.first else { return }

            var pose = BodyPose()
            let jointNames: [VNHumanBodyPoseObservation.JointName] = [
                .nose, .leftShoulder, .rightShoulder,
                .leftElbow, .rightElbow, .leftWrist, .rightWrist,
                .leftHip, .rightHip, .neck, .root
            ]

            for name in jointNames {
                guard let point = try? observation.recognizedPoint(name),
                      point.confidence > self.confidenceThreshold else { continue }
                pose.joints[name] = CGPoint(x: point.location.x, y: 1 - point.location.y)
            }

            DispatchQueue.main.async {
                self.currentPose = pose
                self.onPose?(pose)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}
