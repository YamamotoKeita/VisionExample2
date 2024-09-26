import UIKit
import Combine
import Vision

class FaceRecognizer {
    // CPUパワーを食い過ぎないよう一回顔認識するたびこの時間待機する
    var trackingInterval: TimeInterval = 0.1

    var lineWidth: CGFloat = 1
    var lineColor: UIColor = UIColor.green

    let facePathSubject = CurrentValueSubject<CGPath?, Never>(nil)

    var trackingTask: Task<Void, Never>?

    private var currentBuffer: CMSampleBuffer?

    func startTracking(buffer: CurrentValueSubject<CVImageBuffer?, Never>) async {
        trackingTask = Task {
            while !Task.isCancelled {
                guard let buffer = currentBuffer else { break }
                currentBuffer = nil

                guard let handler = makeRequestHandler(buffer: buffer) else {
                    // TODO エラー制御
                    break
                }

                let facePath = await recognizeFaces(requestHandeler: handler)
                facePathSubject.send(facePath)

                await Task.sleep(interval: trackingInterval)
            }
        }
    }

    func stopTracking() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    func setImageBuffer(_ buffer: CMSampleBuffer) {
        self.currentBuffer = buffer
    }

    private func makeRequestHandler(buffer: CMSampleBuffer) -> VNImageRequestHandler? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer),
              let exifOrientation = CGImagePropertyOrientation(rawValue: UInt32(exifOrientationFromDeviceOrientation())) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

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
                    // TODO エラー制御
                    print(error)
                }

                guard let self,
                    let faces = request.results as? [VNFaceObservation],
                    let mainFace = selectMainFace(faces: faces) else {
                    continuation.resume(returning: nil)
                    return
                }

                let path = makeFacePath(face: mainFace)
                continuation.resume(returning: path)
            }

            do {
                try requestHandeler.perform([request])
            } catch let error as NSError {
                print("Failed to perform image request: \(error)")
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

        // VNFaceObservationの座標系は左下原点、UIKitの座標系は左上原点なので、上下を反転する
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: face.boundingBox.origin.x, y: 1 - face.boundingBox.origin.y)
        transform = transform.scaledBy(x: 1, y: -1)

        guard let adjustedPath = landmarkPath.copy(using: &transform) else {
            return nil
        }

        return adjustedPath
    }

    //
    // VNFaceObservationの座標系は左下原点、UIKitの座標系は左上原点なので、上下を反転する。
    // また、VNFaceObservationの座標は画像サイズに対する比率なので、描画領域のサイズに合わせて拡大する。
    //
    private func adjustmentTransform(faceBounds: CGRect, canvasSize: CGSize) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: canvasSize.width * faceBounds.origin.x,
                                           y: canvasSize.height * (1 - faceBounds.origin.y))
        transform = transform.scaledBy(x: canvasSize.width * faceBounds.size.width,
                                       y: canvasSize.height * -faceBounds.size.height)
        return transform
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

    //
    // 顔を描画するキャンバスのサイズを計算する。
    // 画像と同じアスペクト比で表示領域にぴったり収まるサイズにする。
    //
    // - Parameters:
    //   - imageSize: 画像のサイズ
    //   - bounds: 画像を表示する領域（UIImageViewなど）のサイズ
    //   - scaleMode: 拡大縮小の方法
    //
    private func calcCanvasSize(imageSize: CGSize, bounds: CGSize, scaleMode: ScaleMode) -> CGSize {
        let boundsRatio = bounds.width / bounds.height
        let imageRatio = imageSize.width / imageSize.height

        let scale = switch scaleMode {
        case .fill:
            if boundsRatio > imageRatio {
                bounds.width / imageSize.width
            } else {
                bounds.height / imageSize.height
            }
        case .fit:
            if boundsRatio > imageRatio {
                bounds.height / imageSize.height
            } else {
                bounds.width / imageSize.width
            }
        }

        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
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

    // 描画領域に対する拡大・縮小方法
    enum ScaleMode {
        case fill
        case fit
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
