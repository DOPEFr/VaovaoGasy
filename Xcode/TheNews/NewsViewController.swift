//
//  NewsViewController.swift
//  TheNews
//
//  Created by Daniel on 4/10/20.
//  Copyright © 2020 dk. All rights reserved.
//

import UIKit
import SafariServices

class NewsViewController: UIViewController {
    // Data
    private var items: [Article] = []
    private let downloader = ImageDownloader()
    private var settings = Settings()

    // UI
    private var collectionView: UICollectionView?
    private let refreshControl = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()

        setup()
        config()
        loadData(settings.category.rawValue)
    }
}

extension NewsViewController: Configurable {
    func setup() {
        // Refresh control
        refreshControl.addTarget(self, action: #selector(loadDataForCurrentCategory), for: UIControl.Event.valueChanged)

        // Navigation item
        let styleImage = UIImage(systemName: "textformat.size")
        let styleBarbutton = UIBarButtonItem(image: styleImage, style: .plain, target: self, action: #selector(selectStyle))
        styleBarbutton.tintColor = .systemGray
        navigationItem.rightBarButtonItems = [styleBarbutton]

        // Collection view
        collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: listInsetFixedHeightLayout)
        collectionView?.dataSource = self
        collectionView?.delegate = self
        collectionView?.backgroundColor = .systemBackground
        collectionView?.showsVerticalScrollIndicator = false
        collectionView?.registerCells()
    }

    func config() {
        // Refresh control
        collectionView?.addSubview(refreshControl)

        // Collection view
        guard let cv = collectionView else { return }

        cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubviewForAutoLayout(cv)
    }
}

private extension NewsViewController {
    func loadData(_ category: String) {
        title = "\(settings.category.rawValue.capitalizingFirstLetter()) News"

        guard let url = NewsApi.urlForCategory(category) else {
            print("load data error")
            return
        }

        items = []
        collectionView?.reloadData()

        NewsApi.getArticles(url: url) { [weak self] (articles) in
            self?.refreshControl.endRefreshing()

            guard let articles = articles else {
                let ac = UIAlertController(title: nil, message: "Could not get articles 😅", preferredStyle: .alert)
                ac.addAction(
                    UIAlertAction.init(title: "OK", style: .default, handler: nil)
                )
                self?.present(ac, animated: true, completion: nil)
                return
            }

            self?.items = articles
            self?.reload()
        }
    }
}

extension NewsViewController: Selectable {
    func didSelect(_ category: String) {
        loadData(category)

        guard let c = NewsCategory(rawValue: category) else { return }
        
        settings.category = c
    }
}

// MARK: - Collection view
extension NewsViewController: UICollectionViewDataSource {
    enum Section: Int, CaseIterable {
        case categories
        case articles
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }

        switch section {
        case .articles:
            return items.count
        default:
            return NewsCategory.allCases.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let section = Section(rawValue: indexPath.section) else { return NytCell() }

        switch section {

        case .categories:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LabelCell.ReuseIdentifier, for: indexPath) as! LabelCell
            
            let name = NewsCategory.allCases[indexPath.row].rawValue.capitalizingFirstLetter()
            cell.configure(name, settings.category.rawValue == name.lowercased())

            return cell

        case .articles:
            let article = items[indexPath.row]
            let identifier = article.identifier

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: settings.style.rawValue, for: indexPath) as! NewsCell
            cell.configure(article)
            downloader.getImage(imageUrl: article.urlToImage, size: cell.imageSizeUnwrapped) { (image) in
                cell.update(image: image, matchingIdentifier: identifier)
            }

            switch settings.style {
            case .bbc:
                let thisCell = cell as? BbcCell
                thisCell?.configure(badgeNumber: indexPath.row + 1)

            case .facebook, .flipboard, .reddit, .twitter:
                downloader.getImage(imageUrl: article.urlToSourceLogo, size: CGSize(width: 60, height: 60)) { (image) in
                    let thisCell = cell as? NewsProfileCell
                    thisCell?.updateSourceLogo(image: image, matchingIdentifier: identifier)
                }
                
            default:
                ()
            }

            return cell
        }
    }
}

extension NewsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else { return }
        
        switch section {
        case .articles:
            let article = items[indexPath.row]
            guard let url = article.url else { return }

            let safariViewController = SFSafariViewController(url: url)
            safariViewController.modalPresentationStyle = .formSheet
            self.present(safariViewController, animated: true, completion: nil)

        default:
            let categories = NewsCategory.allCases
            let c = categories[indexPath.row]

            settings.category = c
            loadData(c.rawValue)
        }
    }
}

// MARK: - Layout
private extension NewsViewController {
    func reload() {
        updateLayout(settings.style)

        collectionView?.reloadData()

        let topIndexPath = IndexPath(row: 0, section: 0)
        collectionView?.scrollToItem(at: topIndexPath, at: .top, animated: false)
    }

    func updateLayout(_ style: NewsStyle) {
        switch style {
        case .lilnews:
            collectionView?.backgroundColor = .systemBackground
            view.backgroundColor = .systemBackground
            collectionView?.collectionViewLayout = imageLayout

        case .reddit, .flipboard:
            collectionView?.backgroundColor = .newsLightGray
            view.backgroundColor = .newsLightGray
            collectionView?.collectionViewLayout = listFullWidthLayout

        case .bbc:
            collectionView?.backgroundColor = .newsLightGray
            view.backgroundColor = .newsLightGray
            collectionView?.collectionViewLayout = listInsetFixedHeightLayout

        default:
            collectionView?.backgroundColor = .systemBackground
            view.backgroundColor = .systemBackground
            collectionView?.collectionViewLayout = listFullWidthLayout
        }
    }

    var imageLayout: UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { sectionNumber, env -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionNumber) {
            case .articles:
                return self.imageSection
            default:
                return self.categoriesSection
            }
        }
    }

    var listFullWidthLayout: UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { sectionNumber, env -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionNumber) {
            case .articles:
                return self.listFullWidthSection
            default:
                return self.categoriesSection
            }
        }
    }

    var listInsetLayout: UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { sectionNumber, env -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionNumber) {
            case .articles:
                return self.listInsetSection
            default:
                return self.categoriesSection
            }
        }
    }

    var listInsetFixedHeightLayout: UICollectionViewLayout {
        return UICollectionViewCompositionalLayout { sectionNumber, env -> NSCollectionLayoutSection? in
            switch Section(rawValue: sectionNumber) {
            case .articles:
                return self.listInsetFixedSection
            default:
                return self.categoriesSection
            }
        }
    }

    var categoriesSection: NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(0.33),
                                              heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .absolute(44))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize,
                                                       subitem: item, count: 3)
        group.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging

        return section
    }

    var imageSection: NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(1),
            heightDimension: NSCollectionLayoutDimension.fractionalHeight(0.895)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)

        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .paging

        return section
    }

    var listFullWidthSection: NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(1),
            heightDimension: NSCollectionLayoutDimension.estimated(450)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10

        return section
    }

    var listInsetSection: NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(1),
            heightDimension: NSCollectionLayoutDimension.estimated(100)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)

        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)

        let inset = view.readableInset
        group.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10

        return section
    }

    var listInsetFixedSection: NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: NSCollectionLayoutDimension.fractionalWidth(1),
            heightDimension: NSCollectionLayoutDimension.absolute(90)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)

        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitem: item, count: 1)

        let inset = view.readableInset
        group.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10

        return section
    }
}

// MARK: - OBJC
private extension NewsViewController {
    @objc
    func loadDataForCurrentCategory() {
        loadData(settings.category.rawValue)
    }

    @objc
    func selectStyle(_ sender: UIBarButtonItem) {
        let ac = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        ac.fixiOSAlertControllerAutolayoutConstraint()

        if let popoverController = ac.popoverPresentationController {
            popoverController.barButtonItem = sender
        }

        for s in NewsStyle.allCases {
            ac.addAction(UIAlertAction(title: s.rawValue, style: .default, handler: handleStyle))
        }

        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        present(ac, animated: true, completion: nil)
    }

    func handleStyle(_ action: UIAlertAction) {
        guard let selected = action.title else { return }

        let styles = NewsStyle.allCases
        let filtered = styles.filter { $0.rawValue == selected }
        guard let style = filtered.first else { return }

        settings.style = style
        reload()
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}

private extension UICollectionView {
    func registerCells() {
        register(LabelCell.self, forCellWithReuseIdentifier: LabelCell.ReuseIdentifier)

        register(TwitterCell.self, forCellWithReuseIdentifier: NewsStyle.twitter.rawValue)
        register(FacebookCell.self, forCellWithReuseIdentifier: NewsStyle.facebook.rawValue)
        register(NytCell.self, forCellWithReuseIdentifier: NewsStyle.nyt.rawValue)
        register(BbcCell.self, forCellWithReuseIdentifier: NewsStyle.bbc.rawValue)
        register(RedditCell.self, forCellWithReuseIdentifier: NewsStyle.reddit.rawValue)
        register(CnnCell.self, forCellWithReuseIdentifier: NewsStyle.cnn.rawValue)
        register(LilCell.self, forCellWithReuseIdentifier: NewsStyle.lilnews.rawValue)
        register(FlipboardCell.self, forCellWithReuseIdentifier: NewsStyle.flipboard.rawValue)
        register(WashingtonCell.self, forCellWithReuseIdentifier: NewsStyle.washingtonPost.rawValue)
        register(WsjCell.self, forCellWithReuseIdentifier: NewsStyle.wsj.rawValue)
    }
}

private extension UIColor {
    static let newsLightGray = UIColor.colorFor(red: 228, green: 229, blue: 230)
}

private extension UIView {

    var readableInset: CGFloat {
        return readableContentGuide.layoutFrame.origin.x
    }

}

