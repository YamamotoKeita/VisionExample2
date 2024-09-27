//
// 顔認識と認識した顔パーツの描画を行う
//
import UIKit
import Combine
import Vision

class FaceRecognizer {
    // CPUパワーを食い過ぎないよう一回顔認識するたびこの時間待機する
    var trackingInterval: TimeInterval = 0.1

    let facePathSubject = CurrentValueSubject<CGPath?, Never>(nil)

    var trackingTask: Task<Void, Never>?

    var isTracking: Bool {
        trackingTask != nil
    }

    let outputView = OutputView()

    private var currentBuffer: CMSampleBuffer?
    private var bag = Set<AnyCancellable>()

    init() {
        facePathSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.outputView.facePath = $0
            }
            .store(in: &bag)
    }

    // 顔のトラッキングを開始する
    func startTracking() {
        guard trackingTask == nil else { return }

        trackingTask = Task {
            // キャンセルされるまで無限ループで顔認識
            while !Task.isCancelled {
                guard let buffer = currentBuffer else { continue }
                currentBuffer = nil

                guard let handler = makeRequestHandler(buffer: buffer) else {
                    continue
                }

                let facePath = await recognizeFaces(requestHandeler: handler)
                facePathSubject.send(facePath)

                await Task.sleep(interval: trackingInterval)
            }
        }
    }

    // 顔のトラッキングを停止する
    func stopTracking() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    // 顔認識対象のイメージバッファをセットする
    func setImageBuffer(_ buffer: CMSampleBuffer?) {
        self.currentBuffer = buffer
    }

    private func makeRequestHandler(buffer: CMSampleBuffer) -> VNImageRequestHandler? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer),
              let exifOrientation = CGImagePropertyOrientation(rawValue: UInt32(exifOrientationFromDeviceOrientation())) else { return nil }
        return VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
    }

    // テスト用。UIImageを対象に顔認識するとき使う
    private func makeRequestHandler(image: UIImage) -> VNImageRequestHandler? {
        guard let cgImage = image.cgImage,
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue)) else {
            return nil
        }
        return VNImageRequestHandler(cgImage: cgImage,
                                     orientation: orientation,
                                     options: [:])
    }

    private func recognizeFaces(requestHandeler: VNImageRequestHandler) async -> CGPath? {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
                if let error {
                    print("顔認識に失敗しました。\(error)")
                    return
                }

                guard let self,
                    let faces = request.results as? [VNFaceObservation],
                    let mainFace = selectMainFace(faces: faces) else {
                    // 顔検出なし
                    continuation.resume(returning: nil)
                    return
                }

                let path = makeFacePath(face: mainFace)
                continuation.resume(returning: path)
            }

            do {
                try requestHandeler.perform([request])
            } catch let error as NSError {
                print("顔認識に失敗しました。\(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    func makeFacePath(face: VNFaceObservation) -> CGPath? {
        guard let landmarks = face.landmarks else {
            return nil
        }

        let landmarkPath = CGMutablePath()

        // 閉じてないpathを描画
        let openLandmarkRegions: [VNFaceLandmarkRegion2D] = [
            landmarks.leftEyebrow,
            landmarks.rightEyebrow,
            landmarks.faceContour,
        ].compactMap { $0 }

        openLandmarkRegions.forEach { region in
            landmarkPath.addRegion(region: region,
                                   isClosed: false)
        }

        // 閉じてるpathを描画
        let closedLandmarkRegions = [
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.outerLips,
            landmarks.nose
        ].compactMap { $0 }

        closedLandmarkRegions.forEach { region in
            landmarkPath.addRegion(region: region,
                                   isClosed: true)
        }

        // VNFaceObservationの座標系は左下原点、UIKitの座標系は左上原点なので上下を反転する（何故か左右も反転する必要があった）
        // また、幅高さを認識した顔のboundingのサイズにする
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: 1 - face.boundingBox.origin.x, y: 1 - face.boundingBox.origin.y)
        transform = transform.scaledBy(x: -face.boundingBox.width, y: -face.boundingBox.height)

        guard let adjustedPath = landmarkPath.copy(using: &transform) else {
            return nil
        }

        return adjustedPath
    }

    //
    // 複数の顔から一番面積の大きい顔を抜き出す
    //
    private func selectMainFace(faces: [VNFaceObservation]) -> VNFaceObservation? {
        faces.sorted(by: {
            $0.boundingBox.area > $1.boundingBox.area
        })
        .first
    }

    private func exifOrientationFromDeviceOrientation() -> Int32 {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .portraitUpsideDown:
            return 8
        case .landscapeLeft:
            return 3
        case .landscapeRight:
            return 1
        default:
            return 6
        }
    }

    // 顔認識結果を描画するView
    class OutputView: UIView {
        var lineWidth: CGFloat = 1
        var lineColor: UIColor = UIColor.green

        var facePath: CGPath? {
            didSet {
                setNeedsDisplay()
            }
        }

        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            backgroundColor = .clear
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            setNeedsDisplay()
        }

        open override func draw(_ rect: CGRect) {
            super.draw(rect) // backgroundColorが塗られる
            guard let context = UIGraphicsGetCurrentContext(), let facePath else { return }

            var transform = CGAffineTransform(scaleX: rect.width, y: rect.height)
            guard let path = facePath.copy(using: &transform) else { return }

            context.setLineWidth(lineWidth)
            context.setStrokeColor(lineColor.cgColor)
            context.addPath(path)
            context.strokePath()
        }
    }
}

private extension CGMutablePath {
    func addRegion(region: VNFaceLandmarkRegion2D, isClosed: Bool) {
        guard region.pointCount > 1 else { return }

        addLines(between: region.normalizedPoints)
        if isClosed {
            closeSubpath()
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(interval: TimeInterval) async {
        try? await sleep(nanoseconds: UInt64(interval * Double(1_000_000_000)))
    }
}
