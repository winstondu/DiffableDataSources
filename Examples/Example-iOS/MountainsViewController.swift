import DiffableDataSources
import UIKit

final class MountainsViewController: UIViewController {
    enum Section {
        case main
    }

    struct Mountain: Hashable {
        var name: String
        var highlightedName: NSAttributedString

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }

        func contains(_ filter: String) -> Bool {
            guard !filter.isEmpty else {
                return true
            }

            let lowercasedFilter = filter.lowercased()
            return name.lowercased().contains(lowercasedFilter)
        }
    }

    @IBOutlet private var searchBar: UISearchBar!
    @IBOutlet private var collectionView: SmartUICollectionView!

    private lazy var dataSource = CollectionViewDiffableDataSource<Section, Mountain>(collectionView: collectionView) { collectionView, indexPath, mountain in
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LabelCell.name, for: indexPath) as! LabelCell
        cell.label.attributedText = mountain.highlightedName
        return cell
    }

    private let allMountains: [Mountain] = mountainsRawData.components(separatedBy: .newlines).map { line in
        let name = line.components(separatedBy: ",")[0]
        return Mountain(name: name, highlightedName: NSAttributedString(string: name))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Mountains Search"

        searchBar.delegate = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: LabelCell.name, bundle: .main), forCellWithReuseIdentifier: LabelCell.name)
        collectionView.allowsMultipleSelection = true

        search(filter: "")
    }

    func search(filter: String) {
        let mountains = allMountains.lazy
            .filter { $0.contains(filter) }
            .sorted { $0.name < $1.name }
            .map { mountain -> Mountain in
                let attrName = underlineOccurences(of: filter.lowercased(), in: NSMutableAttributedString(string: mountain.name))
                return Mountain(name: mountain.name, highlightedName: attrName)
            }

        var snapshot = DiffableDataSourceSnapshot<Section, Mountain>()
        snapshot.appendSections([.main])
        snapshot.appendItems(mountains)
        dataSource.apply(snapshot)
    }
}

private func underlineOccurences(of searchString: String, in text: NSMutableAttributedString) -> NSMutableAttributedString {
    let inputLength = text.string.count
    let searchLength = searchString.count
    var range = NSRange(location: 0, length: text.length)

    while range.location != NSNotFound {
        range = (text.string.lowercased() as NSString).range(of: searchString, options: [], range: range)
        if range.location != NSNotFound {
            text.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: range.location, length: searchLength))
            range = NSRange(location: range.location + range.length, length: inputLength - (range.location + range.length))
        }
    }
    return text
}

extension MountainsViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        search(filter: searchText)
    }
}

extension MountainsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let column = 2
        let width = (collectionView.bounds.width - 10 * CGFloat(column + 1)) / CGFloat(column)
        return CGSize(width: width, height: 32)
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? LabelCell {
            cell.label.textColor = .red
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        didDeselectItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? LabelCell {
            cell.label.textColor = .black
        }
    }
}

// A smarter UICollectionView intended to be used with diffable data sources (or any datasource that conforms to Apple's guideline of processing cell reloads first, BEFORE deletes & inserts)
// When a reload occurs on an indexPath where the corresponding cell still exists, it will always return that cell on associated data source's corresponding dequeue for the indexPath (instead of taking a random other cell).
// During data updates, you can take advantage of this fact as follows:
// The datasource's CellProvider function (a.k.a. `func collectionView(UICollectionView, cellForItemAt: IndexPath) -> UICollectionViewCell`) should check, when the collectionview is in reloadMode, if the cell dequeued already has the same signature as the data you were intending to update it with. In those cases, just provide an incremental update (instead of full reset of the cell's visual elements)
open class SmartUICollectionView: UICollectionView {
    open override func dequeueReusableCell(withReuseIdentifier identifier: String, for indexPath: IndexPath) -> UICollectionViewCell {
        if currentMode == .reload, let cell = self.cellForItem(at: indexPath), cell.reuseIdentifier == identifier {
            return cell
        } else {
            return super.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)
        }
    }

    open override func reloadItems(at indexPaths: [IndexPath]) {
        var needsReload: [IndexPath] = []
        for index in indexPaths {
            if let cell = self.cellForItem(at: index) {
                currentMode = .reload
                let newCell = dataSource?.collectionView(self, cellForItemAt: index)
                // The references should be to the exact same cell. In the error case they are not, do a true reload.
                if cell != newCell {
                    needsReload.append(index)
                }
            } else {
                needsReload.append(index)
            }
        }
        super.reloadItems(at: needsReload)
    }

    open override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) {
        currentMode = .move
        super.moveItem(at: indexPath, to: newIndexPath)
    }

    open override func insertItems(at indexPaths: [IndexPath]) {
        currentMode = .insert
        super.insertItems(at: indexPaths)
    }

    open override func deleteItems(at indexPaths: [IndexPath]) {
        currentMode = .delete
        super.deleteItems(at: indexPaths)
    }

    func reloadItemsWithoutReuse(at indexPaths: [IndexPath]) {
        super.reloadItems(at: indexPaths)
    }

    open override func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        super.performBatchUpdates(updates, completion: { status in
            self.currentMode = .none
            completion?(status)
        })
    }

    enum DequeueMode: CaseIterable {
        case reload
        case move
        case insert
        case delete
        case none
    }

    var currentMode: DequeueMode = .none
}
