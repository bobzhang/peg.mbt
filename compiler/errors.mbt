///|
/// A semantic error in the grammar, reported at `location`
/// (PEG.js' `GrammarError`).
#derive(Debug)
pub(all) suberror GrammarError {
  GrammarError(message~ : String, location~ : @runtime.Location)
}

///|
pub impl Show for GrammarError with fn output(self, logger) {
  let GrammarError(message~, ..) = self
  logger.write_string("GrammarError: ")
  logger.write_string(message)
}

///|
/// A compiler error without a source location (a plain `Error` in PEG.js).
#derive(Debug)
pub(all) suberror CompilerError {
  CompilerError(String)
}

///|
pub impl Show for CompilerError with fn output(self, logger) {
  let CompilerError(message) = self
  logger.write_string("Error: ")
  logger.write_string(message)
}
