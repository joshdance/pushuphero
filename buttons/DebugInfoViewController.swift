//
//  DebugInfoViewController.swift
//  Pushup Hero
//
//  Diagnostics modal, opened by a three-finger tap on the stats screen.
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
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        let header = UILabel()
        header.text = "Diagnostics"
        header.font = UIFont.boldSystemFont(ofSize: 20)
        header.textAlignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            header.textColor = .label
        }

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
        if #available(iOS 13.0, *) {
            textView.backgroundColor = .systemBackground
            textView.textColor = .label
        }

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

// MARK: - Stats

/// Lifetime totals, opened by tapping the "Pushup Hero" title.
/// A three-finger tap on this screen still opens diagnostics.
class StatsViewController: UIViewController, UIGestureRecognizerDelegate {

    private let workouts: [DataObject]
    private let loadFailed: Bool

    private let titleLabel = UILabel()
    private let totalCard = UIView()
    private let totalLabel = UILabel()
    private let totalCaption = UILabel()
    private let perYearCaption = UILabel()
    private let yearsCard = UIView()
    private let yearsStack = UIStackView()
    private let closeButton = UIButton(type: .system)

    private var cards: [UIView] = []
    private var primaryLabels: [UILabel] = []
    private var secondaryLabels: [UILabel] = []
    private var separators: [UIView] = []

    init(workouts: [DataObject], loadFailed: Bool) {
        self.workouts = workouts
        self.loadFailed = loadFailed
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let totals = yearlyTotals()

        closeButton.setTitle("Close", for: .normal)
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Pushup Hero"
        titleLabel.font = UIFont(name: "Helvetica-Bold", size: 29) ?? UIFont.boldSystemFont(ofSize: 29)
        titleLabel.textAlignment = .center
        titleLabel.textColor = popColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureCard(totalCard)
        totalLabel.text = String(totals.allTime)
        totalLabel.font = UIFont.systemFont(ofSize: 48)
        totalLabel.textAlignment = .center
        totalLabel.translatesAutoresizingMaskIntoConstraints = false
        totalCaption.text = "all time"
        totalCaption.font = UIFont.systemFont(ofSize: 23)
        totalCaption.textAlignment = .center
        totalCaption.translatesAutoresizingMaskIntoConstraints = false
        totalCard.addSubview(totalLabel)
        totalCard.addSubview(totalCaption)
        primaryLabels.append(totalLabel)
        secondaryLabels.append(totalCaption)

        perYearCaption.text = "per year"
        perYearCaption.font = UIFont.systemFont(ofSize: 23)
        perYearCaption.textAlignment = .center
        perYearCaption.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabels.append(perYearCaption)

        configureCard(yearsCard)
        yearsStack.axis = .vertical
        yearsStack.translatesAutoresizingMaskIntoConstraints = false
        yearsCard.addSubview(yearsStack)

        if totals.years.isEmpty {
            let empty = UILabel()
            empty.text = "No workouts yet"
            empty.font = UIFont.systemFont(ofSize: 17)
            empty.textAlignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            yearsStack.addArrangedSubview(paddedRow(empty, height: 52))
            secondaryLabels.append(empty)
        } else {
            for (index, entry) in totals.years.enumerated() {
                if index > 0 {
                    let line = UIView()
                    line.translatesAutoresizingMaskIntoConstraints = false
                    line.heightAnchor.constraint(equalToConstant: 1).isActive = true
                    yearsStack.addArrangedSubview(line)
                    separators.append(line)
                }
                yearsStack.addArrangedSubview(yearRow(year: entry.year, count: entry.count))
            }
        }

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let content = UIStackView(arrangedSubviews: [totalCard, perYearCaption, yearsCard])
        content.axis = .vertical
        content.spacing = 20
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(scrollView)

        let guide: UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = view.safeAreaLayoutGuide
        } else {
            guide = view.layoutMarginsGuide
        }

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),

            content.topAnchor.constraint(equalTo: scrollView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            totalCard.heightAnchor.constraint(equalToConstant: 140),
            totalLabel.centerXAnchor.constraint(equalTo: totalCard.centerXAnchor),
            totalLabel.centerYAnchor.constraint(equalTo: totalCard.centerYAnchor, constant: -16),
            totalCaption.centerXAnchor.constraint(equalTo: totalCard.centerXAnchor),
            totalCaption.topAnchor.constraint(equalTo: totalLabel.bottomAnchor, constant: 4),

            yearsStack.topAnchor.constraint(equalTo: yearsCard.topAnchor, constant: 4),
            yearsStack.leadingAnchor.constraint(equalTo: yearsCard.leadingAnchor),
            yearsStack.trailingAnchor.constraint(equalTo: yearsCard.trailingAnchor),
            yearsStack.bottomAnchor.constraint(equalTo: yearsCard.bottomAnchor, constant: -4)
        ])

        let threeFingerTap = UITapGestureRecognizer(target: self, action: #selector(showDiagnostics))
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.delegate = self
        threeFingerTap.cancelsTouchesInView = false
        view.addGestureRecognizer(threeFingerTap)

        applyInterfaceColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                applyInterfaceColors()
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func showDiagnostics() {
        let report = DataMigrationManager.shared.debugReport(inMemoryCount: workouts.count,
                                                             loadFailed: loadFailed)
        let debugViewController = DebugInfoViewController(report: report)
        debugViewController.modalPresentationStyle = .fullScreen
        present(debugViewController, animated: true, completion: nil)
    }

    private func yearlyTotals() -> (allTime: Int, years: [(year: Int, count: Int)]) {
        let calendar = Calendar.current
        var byYear: [Int: Int] = [:]
        var allTime = 0

        for workout in workouts {
            allTime = allTime + workout.numberOfPushups
            let year = calendar.component(.year, from: workout.dateOfWorkout)
            if let current = byYear[year] {
                byYear[year] = current + workout.numberOfPushups
            } else {
                byYear[year] = workout.numberOfPushups
            }
        }

        var years: [(year: Int, count: Int)] = []
        let sortedYears = Array(byYear.keys).sorted(by: { $0 > $1 })
        for year in sortedYears {
            years.append((year: year, count: byYear[year] ?? 0))
        }
        return (allTime, years)
    }

    private func configureCard(_ card: UIView) {
        card.layer.borderWidth = 2.0
        card.layer.cornerRadius = 10.0
        card.translatesAutoresizingMaskIntoConstraints = false
        cards.append(card)
    }

    private func yearRow(year: Int, count: Int) -> UIView {
        let yearLabel = UILabel()
        yearLabel.text = String(year)
        yearLabel.font = UIFont.systemFont(ofSize: 23)
        yearLabel.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = UILabel()
        countLabel.text = String(count)
        countLabel.font = UIFont.systemFont(ofSize: 24)
        countLabel.textAlignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        secondaryLabels.append(yearLabel)
        primaryLabels.append(countLabel)

        let row = UIView()
        row.addSubview(yearLabel)
        row.addSubview(countLabel)
        NSLayoutConstraint.activate([
            yearLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            yearLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            countLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: yearLabel.trailingAnchor, constant: 12),
            row.heightAnchor.constraint(equalToConstant: 52)
        ])
        return row
    }

    private func paddedRow(_ label: UILabel, height: CGFloat) -> UIView {
        let row = UIView()
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: height)
        ])
        return row
    }

    private func applyInterfaceColors() {
        let background: UIColor
        let card: UIColor
        let border: UIColor
        let fieldText: UIColor
        let muted: UIColor

        if #available(iOS 13.0, *) {
            background = .systemBackground
            card = .secondarySystemBackground
            border = .separator
            fieldText = .label
            muted = .secondaryLabel
        } else {
            background = .white
            card = .white
            border = borderColor
            fieldText = .black
            muted = UIColor(white: 0.45, alpha: 1)
        }

        view.backgroundColor = background
        let borderCG = border.cgColor
        for box in cards {
            box.backgroundColor = card
            box.layer.borderColor = borderCG
        }
        for label in primaryLabels {
            label.textColor = fieldText
        }
        for label in secondaryLabels {
            label.textColor = muted
        }
        for line in separators {
            line.backgroundColor = border
        }
    }
}
