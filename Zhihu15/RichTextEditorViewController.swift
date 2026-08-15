import PhotosUI
import UIKit

final class RichTextEditorViewController: UIViewController, PHPickerViewControllerDelegate {
    enum Mode {
        case answer(questionID: Int64, questionTitle: String)
        case pin
    }

    private let mode: Mode
    private let titleField = UITextField()
    private let textView = UITextView()
    private let repository = ZhihuCreationRepository.shared
    private var draftKey: String { switch mode { case let .answer(id, _): return "answer-\(id)"; case .pin: return "pin" } }

    init(mode: Mode) { self.mode = mode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = modeTitle
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "保存", style: .plain, target: self, action: #selector(saveDraft)),
            UIBarButtonItem(title: "发布", style: .done, target: self, action: #selector(publish))
        ]
        setupViews()
        if let draft = UserDefaults.standard.string(forKey: "zhihu15.draft.\(draftKey)") { textView.text = draft }
    }

    private var modeTitle: String {
        switch mode { case .answer: return "写回答"; case .pin: return "发想法" }
    }

    private func setupViews() {
        titleField.placeholder = modeTitle == "发想法" ? "标题（可选）" : "回答标题"
        titleField.font = .systemFont(ofSize: 21, weight: .semibold)
        titleField.borderStyle = .none
        titleField.isHidden = modeTitle != "发想法"
        titleField.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 17)
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            titleField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleField.heightAnchor.constraint(equalToConstant: 34),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: titleField.isHidden ? view.safeAreaLayoutGuide.topAnchor : titleField.bottomAnchor, constant: 10),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        textView.inputAccessoryView = makeToolbar()
    }

    private func makeToolbar() -> UIView {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        let bold = UIBarButtonItem(title: "B", style: .plain, target: self, action: #selector(toggleBold))
        let italic = UIBarButtonItem(title: "I", style: .plain, target: self, action: #selector(toggleItalic))
        let underline = UIBarButtonItem(title: "U", style: .plain, target: self, action: #selector(toggleUnderlineFormatting))
        let image = UIBarButtonItem(image: UIImage(systemName: "photo"), style: .plain, target: self, action: #selector(insertImage))
        toolbar.items = [bold, italic, underline, UIBarButtonItem.flexibleSpace(), image]
        return toolbar
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func toggleBold() { toggleTrait(.traitBold) }
    @objc private func toggleItalic() { toggleTrait(.traitItalic) }
    @objc private func toggleUnderlineFormatting() {
        let range = textView.selectedRange
        guard range.length > 0 else { return }
        textView.textStorage.enumerateAttribute(.underlineStyle, in: range) { value, subrange, _ in
            let current = (value as? NSNumber)?.intValue ?? 0
            self.textView.textStorage.addAttribute(.underlineStyle, value: current == 0 ? NSUnderlineStyle.single.rawValue : 0, range: subrange)
        }
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        let range = textView.selectedRange
        guard range.length > 0 else { return }
        textView.textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? UIFont) ?? UIFont.systemFont(ofSize: 17)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            self.textView.textStorage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
        }
    }

    @objc private func insertImage() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: -4, width: min(image.size.width, 260), height: min(image.size.height, 220))
                let attributed = NSAttributedString(attachment: attachment)
                self.textView.textStorage.insert(attributed, at: self.textView.selectedRange.location)
            }
        }
    }

    @objc private func saveDraft() {
        UserDefaults.standard.set(textView.text, forKey: "zhihu15.draft.\(draftKey)")
        switch mode {
        case let .answer(questionID, _):
            repository.saveAnswerDraft(questionID: questionID, html: CreationHTMLCompiler.html(from: textView.text)) { [weak self] result in self?.showResult(result.map { _ in () }, success: "回答草稿已保存") }
        case .pin: showResult(.success(()), success: "想法草稿已保存")
        }
    }

    @objc private func publish() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { showResult(.failure(ZhihuSessionError.malformedPayload), success: ""); return }
        switch mode {
        case let .answer(questionID, _):
            repository.publishAnswer(questionID: questionID, html: CreationHTMLCompiler.html(from: text)) { [weak self] result in self?.showPublishResult(result) }
        case .pin:
            repository.publishPin(title: titleField.text ?? "", text: text) { [weak self] result in self?.showPublishResult(result) }
        }
    }

    private func showPublishResult(_ result: Result<Int64, Error>) {
        switch result {
        case .success:
            UserDefaults.standard.removeObject(forKey: "zhihu15.draft.\(draftKey)")
            showResult(.success(()), success: "发布成功")
        case let .failure(error): showResult(.failure(error), success: "")
        }
    }

    private func showResult(_ result: Result<Void, Error>, success: String) {
        let message: String
        switch result { case .success: message = success; case let .failure(error): message = error.localizedDescription }
        let alert = UIAlertController(title: "知乎", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}
