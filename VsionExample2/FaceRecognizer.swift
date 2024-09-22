import UIKit
import Vision

class FaceRecognizer {
    var lineWidth: CGFloat = 1
    var lineColor: UIColor = UIColor.green

    func makeFaceImage(image: UIImage, viewSize: CGSize, scaleMode: ScaleMode) async -> UIImage? {
        guard let cgImage = image.cgImage,
              let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue)) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            startFaceRecognition(cgImage: cgImage,
                             orientation: orientation,
                             viewSize: viewSize,
                             scaleMode: scaleMode,
                             continuation: continuation)
        }
    }

    // 顔認識を開始
    private func startFaceRecognition(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        viewSize: CGSize,
        scaleMode: ScaleMode,
        continuation: CheckedContinuation<UIImage?, Never>?
    ) {
        let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage,
                                                        orientation: orientation,
                                                        options: [:])

        let request = VNDetectFaceLandmarksRequest { [weak self] request, error in
            if let error {
                print(error)
            }
            guard let self,
                let faces = request.results as? [VNFaceObservation],
                let mainFace = selectMainFace(faces: faces) else {
                continuation?.resume(returning: nil)
                return
            }

            let image = drawFaceLines(face: mainFace,
                                      imageSize: CGSize(width: cgImage.width, height: cgImage.height),
                                      bounds: viewSize,
                                      scaleMode: scaleMode)
            continuation?.resume(returning: image)
        }

        do {
            try imageRequestHandler.perform([request])
        } catch let error as NSError {
            print("Failed to perform image request: \(error)")
            continuation?.resume(returning: nil)
        }
    }


    // 顔のパーツを描画する
    private func drawFaceLines(face: VNFaceObservation,
                               imageSize: CGSize,
                               bounds: CGSize,
                               scaleMode: ScaleMode) -> UIImage? {

        guard let landmarks = face.landmarks else {
            return nil
        }

        let canvasSize = self.calcCanvasSize(imageSize: imageSize, bounds: bounds, scaleMode: scaleMode)
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, 0.0)
        guard let context = UIGraphicsGetCurrentContext() else {
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

        var transform = transform(faceBounds: face.boundingBox, canvasSize: canvasSize)

        guard let adjustedPath = landmarkPath.copy(using: &transform) else {
            return nil
        }

        context.setStrokeColor(lineColor.cgColor)
        context.setLineWidth(lineWidth)

        context.addPath(adjustedPath)
        context.strokePath()

        let image = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return image
    }

    //
    // VNFaceObservationの座標系は左下原点、UIKitの座標系は左上原点なので、上下を反転する。
    // また、VNFaceObservationの座標は画像サイズに対する比率なので、描画領域のサイズに合わせて拡大する。
    //
    private func transform(faceBounds: CGRect, canvasSize: CGSize) -> CGAffineTransform {
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
