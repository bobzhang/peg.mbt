///|
/// A compiler pass: inspects or rewrites the grammar, reporting problems
/// through the session. `name` identifies built-in passes (e.g.
/// `"reportUndefinedRules"`), which lets plugins find and replace them.
pub(all) struct Pass[T] {
  name : String
  run : (@ast.Grammar, Session[T], Options[T]) -> Unit raise
}

///|
/// The ordered pass stages `compile` runs.
pub(all) struct Passes[T] {
  mut check : Array[Pass[T]]
  mut transform : Array[Pass[T]]
  mut generate : Array[Pass[T]]
}

///|
/// Compiler configuration handed to plugins (`peg.compiler.Session`).
///
/// Every component can be replaced: the grammar `parser`, the `passes`, the
/// `opcodes` numbering used by bytecode generation, the `warn` / `error`
/// reporters, and the `backend` that turns a compiled grammar into a parser
/// (the counterpart of PEG.js' `vm`).
pub(all) struct Session[T] {
  mut parser : (String, ParserOptions) -> @ast.Grammar raise
  mut passes : Passes[T]
  mut opcodes : @bytecode.Opcodes
  mut warn : (String, @runtime.Location?) -> Unit
  mut error : (String, @runtime.Location?) -> Unit raise
  mut backend : (@ast.Grammar, Session[T], Options[T]) -> @vm.Parser[T] raise
}

///|
/// Raises `GrammarError` when a location is given, `CompilerError`
/// otherwise (`session.fatal`).
pub fn fatal(message : String, location? : @runtime.Location) -> Unit raise {
  match location {
    Some(location) => raise GrammarError(message~, location~)
    None => raise CompilerError(message)
  }
}

///|
pub fn[T] Session::new(
  parser~ : (String, ParserOptions) -> @ast.Grammar raise,
  passes? : Passes[T] = default_passes(),
  opcodes? : @bytecode.Opcodes = @bytecode.default_opcodes,
  warn? : (String, @runtime.Location?) -> Unit = (_, _) => (),
  error? : (String, @runtime.Location?) -> Unit raise = (m, l) => {
    fatal(m, location?=l)
  },
  backend? : (@ast.Grammar, Session[T], Options[T]) -> @vm.Parser[T] raise = interpreter_backend,
) -> Session[T] {
  { parser, passes, opcodes, warn, error, backend, }
}

///|
pub fn[T] Session::parse(
  self : Session[T],
  input : String,
  options : ParserOptions,
) -> @ast.Grammar raise {
  (self.parser)(input, options)
}

///|
pub fn[T] Session::report_error(
  self : Session[T],
  message : String,
  location? : @runtime.Location,
) -> Unit raise {
  (self.error)(message, location)
}

///|
pub fn[T] Session::report_warning(
  self : Session[T],
  message : String,
  location? : @runtime.Location,
) -> Unit {
  (self.warn)(message, location)
}

///|
/// The standard passes, in PEG.js order.
pub fn[T] default_passes() -> Passes[T] {
  {
    check: [
      { name: "reportUndefinedRules", run: report_undefined_rules, },
      { name: "reportDuplicateRules", run: report_duplicate_rules, },
      { name: "reportUnusedRules", run: report_unused_rules, },
      { name: "reportDuplicateLabels", run: report_duplicate_labels, },
      { name: "reportInfiniteRecursion", run: report_infinite_recursion, },
      { name: "reportInfiniteRepetition", run: report_infinite_repetition, },
      { name: "reportIncorrectPlucking", run: report_incorrect_plucking, },
    ],
    transform: [{ name: "removeProxyRules", run: remove_proxy_rules, }],
    generate: [
      { name: "calcReportFailures", run: calc_report_failures, },
      { name: "inferenceMatchResult", run: inference_match_result, },
      { name: "generateBytecode", run: generate_bytecode, },
    ],
  }
}
