import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var overlayImageView: UIImageView!
    @IBOutlet weak var captureView: UIView!
    
    let faceRecognizer = FaceRecognizer()
    let videoCapture = VideoCapture()

    override func viewDidLoad() {
        super.viewDidLoad()
        overlayImageView.contentMode = imageView.contentMode

        videoCapture.addToView(view: captureView)

        Task {
            guard let image = imageView.image,
                  let scaleMode = imageView.contentMode.scaleMode else { return }
            let faceImage = await faceRecognizer.makeFaceImage(image: image,
                                                               viewSize: imageView.frame.size,
                                                               scaleMode: scaleMode)
            overlayImageView.image = faceImage
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoCapture.start()
    }
}

private extension UIView.ContentMode {
    var scaleMode: FaceRecognizer.ScaleMode? {
        switch self {
        case .scaleAspectFit: .fit
        case .scaleAspectFill: .fill
        default: nil
        }
    }
}
