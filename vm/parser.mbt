///|
pub using @runtime {
  type Value,
  type ActionFn,
  type InitFn,
  type Tracer,
  type SyntaxError,
}

///|
/// A generated parser.
///
/// Usually built from a compiled `Program` by `Parser::from_program`, but
/// any parse function can be wrapped (e.g. by compiler plugins).
pub struct Parser[T] {
  priv parse_impl : (String, Map[String, Value[T]], Tracer[T]?) -> Value[T] raise
  /// The program this parser interprets, when it has one.
  program : @bytecode.Program?
}

///|
/// Wraps a parse function. It receives the input, the parse options (which
/// include `startRule` / `filename` when given) and the tracer, if any.
pub fn[T] Parser::from_fn(
  parse : (String, Map[String, Value[T]], Tracer[T]?) -> Value[T] raise,
) -> Parser[T] {
  { parse_impl: parse, program: None, }
}

///|
/// Parses `input`, returning the start rule's result.
///
/// `options` is exposed to actions as PEG.js' `options` object; `start_rule`
/// and `filename` are shorthands for its `startRule` and `filename` entries.
/// Raises `@runtime.SyntaxError` when the input does not match.
pub fn[T] Parser::parse(
  self : Parser[T],
  input : String,
  start_rule? : String,
  filename? : String,
  tracer? : Tracer[T],
  options? : Map[String, Value[T]],
) -> Value[T] raise {
  let options = match options {
    Some(o) => o
    None => {}
  }
  if start_rule is Some(r) {
    options["startRule"] = Str(r)
  }
  if filename is Some(f) {
    options["filename"] = Str(f)
  }
  (self.parse_impl)(input, options, tracer)
}

///|
/// Raised when a code block of the grammar has no MoonBit implementation.
pub(all) suberror UnboundCode {
  UnboundCode(kind~ : String, code~ : String)
} derive(Debug)

///|
pub impl Show for UnboundCode with fn output(self, logger) {
  let UnboundCode(kind~, code~) = self
  logger.write_string("No binding for \{kind} code block {\{code}}")
}

///|
/// Looks up the implementation of code block number `index` (its position
/// in `Program::functions`) with source text `body`. Keys are tried in order:
///
/// 1. `"#<index>"` — exact, but specific to one compilation of the grammar;
/// 2. the exact body text;
/// 3. the body with surrounding whitespace trimmed (so a grammar can simply
///    say `{ makeNumber }`).
///
/// Identical bodies with different labels in scope share a text key, so
/// actions bound by text should read labels by name (`ActionContext::label`).
pub fn[V] lookup_binding(
  bindings : Map[String, V],
  index : Int,
  body : String,
) -> V? {
  match bindings.get("#\{index}") {
    Some(f) => Some(f)
    None =>
      match bindings.get(body) {
        Some(f) => Some(f)
        None => bindings.get(body.trim().to_owned())
      }
  }
}
