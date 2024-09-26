import UIKit
import Combine

class ViewController: UIViewController {

    @IBOutlet weak var captureView: UIView!
    @IBOutlet weak var actionButton: UIButton!

    let faceRecognizer = FaceRecognizer()
    let videoCapture = VideoCapture()

    var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        updateButton()
        observe()

        captureView.addSubview(faceRecognizer.outputView)
        faceRecognizer.outputView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            captureView.topAnchor.constraint(equalTo: faceRecognizer.outputView.topAnchor),
            captureView.bottomAnchor.constraint(equalTo: faceRecognizer.outputView.bottomAnchor),
            captureView.leadingAnchor.constraint(equalTo: faceRecognizer.outputView.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: faceRecognizer.outputView.trailingAnchor)
        ])
    }

    func observe() {
        videoCapture.imageBufferSubject
            .sink { [weak self] in
                guard let self else { return }
                faceRecognizer.setImageBuffer($0)
            }
            .store(in: &bag)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        videoCapture.addToView(view: captureView)
        Task {
            videoCapture.start()
        }
    }

    @IBAction func buttonAction(_ sender: Any) {
        if faceRecognizer.isTracking {
            faceRecognizer.stopTracking()
        } else {
            faceRecognizer.startTracking()
        }
        updateButton()
    }

    func updateButton() {
        let title = faceRecognizer.isTracking ? "顔認識停止" : "顔認識開始"
        actionButton.setTitle(title, for: .normal)
    }
}
