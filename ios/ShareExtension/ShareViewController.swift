import Social
import UIKit

/// Apple's compose UI doesn't reliably auto-fill `contentText` from a plain
/// text share — that only happens when the source app sets
/// `NSExtensionItem.attributedContentText`, and Messages hands the selected
/// text over as a plain-text item-provider attachment instead. So this pulls
/// it out manually and fills the text view itself.
class ShareViewController: SLComposeServiceViewController {
  private let appGroupId = "group.com.kharcha.expensetracker"
  private let pendingSharesKey = "pendingShares"

  override func viewDidLoad() {
    super.viewDidLoad()
    extractSharedText { [weak self] text in
      guard let self = self, let text = text, !text.isEmpty else { return }
      DispatchQueue.main.async {
        self.textView.text = text
        self.validateContent()
      }
    }
  }

  override func isContentValid() -> Bool {
    return !(contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  override func didSelectPost() {
    let text = contentText ?? ""
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let suite = UserDefaults(suiteName: appGroupId)
      var pending = suite?.stringArray(forKey: pendingSharesKey) ?? []
      pending.append(text)
      suite?.set(pending, forKey: pendingSharesKey)
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  override func configurationItems() -> [Any]! {
    return []
  }

  private func extractSharedText(completion: @escaping (String?) -> Void) {
    guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
      completion(nil)
      return
    }
    if let attributed = item.attributedContentText, !attributed.string.isEmpty {
      completion(attributed.string)
      return
    }
    // Let the system pick whichever representation (plain-text, utf8-plain-
    // text, etc.) the source app actually provided, instead of guessing one
    // exact UTI and missing a sibling/child type that doesn't match it.
    guard let attachments = item.attachments,
          let provider = attachments.first(where: { $0.canLoadObject(ofClass: NSString.self) })
    else {
      completion(nil)
      return
    }
    provider.loadObject(ofClass: NSString.self) { object, _ in
      completion(object as? String)
    }
  }
}
