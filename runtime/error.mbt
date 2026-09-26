///|
/// Raised by a parser when the input does not match the grammar, or by the
/// `error()` / `expected()` action helpers.
///
/// `expected` and `found` are `None` for errors raised through `error()`,
/// like the `null` fields of PEG.js' `peg$SyntaxError`.
pub(all) suberror SyntaxError {
  SyntaxError(
    message~ : String,
    expected~ : Array[Expectation]?,
    found~ : String?,
    location~ : Location
  )
} derive(Debug)

///|
pub impl Show for SyntaxError with fn output(self, logger) {
  let SyntaxError(message~, ..) = self
  logger.write_string("SyntaxError: ")
  logger.write_string(message)
}

///|
pub impl ToJson for SyntaxError with fn to_json(self) {
  let SyntaxError(message~, expected~, found~, location~) = self
  {
    "name": "SyntaxError",
    "message": message,
    "expected": match expected {
      Some(e) => e.to_json()
      None => Json::null()
    },
    "found": match found {
      Some(f) => f.to_json()
      None => Json::null()
    },
    "location": location.to_json(),
  }
}

///|
/// Raised when `parse` is asked to start from a rule that is not in the
/// grammar's allowed start rules.
pub(all) suberror InvalidStartRule {
  InvalidStartRule(String)
} derive(Debug)

///|
pub impl Show for InvalidStartRule with fn output(self, logger) {
  let InvalidStartRule(rule) = self
  logger.write_string("Can't start parsing from rule \"")
  logger.write_string(rule)
  logger.write_string("\".")
}

///|
/// Raised when an action calls a helper disabled by the `features` option
/// (in PEG.js the helper is simply undefined).
pub(all) suberror FeatureDisabled {
  FeatureDisabled(String)
} derive(Debug)

///|
pub impl Show for FeatureDisabled with fn output(self, logger) {
  let FeatureDisabled(name) = self
  logger.write_string(name)
  logger.write_string(" is not a function")
}
