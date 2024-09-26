import UIKit
import Combine
import AVFoundation
import Vision

class VideoCapture: NSObject {

    let imageBuffer = CurrentValueSubject<CVImageBuffer?, Never>(nil)
    let captureSession: AVCaptureSession
    let previewLayer: AVCaptureVideoPreviewLayer

    override init() {
        captureSession = AVCaptureSession()
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        super.init()

        setupCaptureSession()
    }

    private func setupCaptureSession() {
        captureSession.sessionPreset = .high

        // フロントカメラを取得
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("フロントカメラが利用できません")
            return
        }

        // カメラ入力を作成
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("カメラ入力を作成できません")
            return
        }
        captureSession.addInput(videoInput)

        // ビデオ出力を作成
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        // プレビューを表示
        previewLayer.videoGravity = .resizeAspectFill
    }

    func start() {
        captureSession.startRunning()
    }

    func addToView(view: UIView) {
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }
}


extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        imageBuffer.send(CMSampleBufferGetImageBuffer(sampleBuffer))
    }
}
