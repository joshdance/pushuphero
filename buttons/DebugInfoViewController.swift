//
//  DebugInfoViewController.swift
//  Pushup Hero
//
//  Diagnostics modal, opened by tapping the "Pushup Hero" title.
//  Read-only: it reports on storage, it never modifies it.
//

import UIKit

class DebugInfoViewController: UIViewController {

    private let report: String
    private let textView = UITextView()

    init(report: String) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let header = UILabel()
        header.text = "Diagnostics"
        header.font = UIFont.boldSystemFont(ofSize: 20)
        header.textAlignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = UIButton(type: .system)
        copyButton.setTitle("Copy", for: .normal)
        copyButton.addTarget(self, action: #selector(copyReport), for: .touchUpInside)
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        textView.text = report
        textView.isEditable = false
        // Monospaced so the aligned sections stay aligned when pasted into an email.
        textView.font = UIFont(name: "Menlo", size: 11) ?? UIFont.systemFont(ofSize: 11)
        textView.alwaysBounceVertical = true
        textView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(header)
        view.addSubview(closeButton)
        view.addSubview(copyButton)
        view.addSubview(textView)

        let guide: UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = view.safeAreaLayoutGuide
        } else {
            guide = view.layoutMarginsGuide
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            header.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),

            copyButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12)
        ])
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func copyReport() {
        UIPasteboard.general.string = report

        let confirmation = UIAlertController(title: nil, message: "Diagnostics copied", preferredStyle: .alert)
        present(confirmation, animated: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                confirmation.dismiss(animated: true, completion: nil)
            }
        }
    }
}
