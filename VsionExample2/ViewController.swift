import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var overlayImageView: UIImageView!

    let faceRecognizer = FaceRecognizer()

    override func viewDidLoad() {
        super.viewDidLoad()
        overlayImageView.contentMode = imageView.contentMode

        Task {
            guard let image = imageView.image,
                  let scaleMode = imageView.contentMode.scaleMode else { return }
            let faceImage = await faceRecognizer.makeFaceImage(image: image,
                                                               viewSize: imageView.frame.size,
                                                               scaleMode: scaleMode)
            overlayImageView.image = faceImage
        }
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
