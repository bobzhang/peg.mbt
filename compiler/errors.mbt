///|
/// A semantic error in the grammar, reported at `location`
/// (PEG.js' `GrammarError`).
pub(all) suberror GrammarError {
  GrammarError(message~ : String, location~ : @runtime.Location)
} derive(Debug)

///|
pub impl Show for GrammarError with fn output(self, logger) {
  let GrammarError(message~, ..) = self
  logger.write_string("GrammarError: ")
  logger.write_string(message)
}

///|
/// A compiler error without a source location (a plain `Error` in PEG.js).
pub(all) suberror CompilerError {
  CompilerError(String)
} derive(Debug)

///|
pub impl Show for CompilerError with fn output(self, logger) {
  let CompilerError(message) = self
  logger.write_string("Error: ")
  logger.write_string(message)
}
