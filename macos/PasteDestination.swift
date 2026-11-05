import Foundation

/// Recheck the intended app immediately before posting a paste, after activation has completed.
struct PasteDestination {
  let processIdentifier: Int32
  func permitsPaste(
    frontmostProcessIdentifier: Int32?, targetTerminated: Bool, clipboard: String?, expected: String
  ) -> Bool {
    !targetTerminated && frontmostProcessIdentifier == processIdentifier && clipboard == expected
  }
}
