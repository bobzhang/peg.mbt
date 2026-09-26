///|
/// Options of the grammar parser (`peg.parser.parse`).
pub(all) struct ParserOptions {
  /// Words that cannot be used as labels; `None` means JavaScript's reserved
  /// words (`util.reservedWords`).
  mut reserved_words : Array[String]?
  /// Collect comments into `Grammar::comments`.
  mut extract_comments : Bool
  /// Source file name recorded in locations.
  mut filename : String?
} derive(Debug)

///|
pub fn ParserOptions::new(
  reserved_words? : Array[String],
  extract_comments? : Bool = false,
  filename? : String,
) -> ParserOptions {
  { reserved_words, extract_comments, filename, }
}

///|
pub(all) enum Optimize {
  Speed
  Size
} derive(Eq, Debug)

///|
pub(all) enum Output {
  /// Return a ready-to-use parser.
  Parser
  /// Return generated MoonBit source code.
  Source
} derive(Eq, Debug)

///|
/// Options of `compile` / `generate`. Plugins may modify them.
pub(all) struct Options[T] {
  /// Rules parsing may start from; `None` means the first rule.
  mut allowed_start_rules : Array[String]?
  mut cache : Bool
  mut optimize : Optimize
  mut output : Output
  mut trace : Bool
  /// Enables/disables generated helpers: `text`, `offset`, `range`,
  /// `location`, `expected`, `error`, `filename`, `DefaultTracer`.
  mut features : Map[String, Bool]
  /// Comment lines placed at the top of generated source.
  mut header : Array[String]
  mut parser : ParserOptions
  /// Implementations of the grammar's action / predicate code blocks, keyed
  /// by code text (the MoonBit analogue of JavaScript code in the grammar).
  mut actions : Map[String, @runtime.ActionFn[T]]
  /// Implementation of the grammar's initializer block.
  mut initializer : @runtime.InitFn[T]?
  /// Payload type `T` of `Value[T]` in generated MoonBit source (a MoonBit
  /// type expression; default `Unit`).
  mut value_type : String
  /// Prefix of the top-level names in generated MoonBit source (lets several
  /// generated parsers share a package).
  mut name_prefix : String
  /// Free-form options for plugins.
  extra : Map[String, Json]
}

///|
pub fn[T] Options::new(
  allowed_start_rules? : Array[String],
  cache? : Bool = false,
  optimize? : Optimize = Speed,
  output? : Output = Parser,
  trace? : Bool = false,
  features? : Map[String, Bool] = {},
  header? : Array[String] = [],
  parser? : ParserOptions = ParserOptions::new(),
  actions? : Map[String, @runtime.ActionFn[T]] = {},
  initializer? : @runtime.InitFn[T],
  value_type? : String = "Unit",
  name_prefix? : String = "",
  extra? : Map[String, Json] = {},
) -> Options[T] {
  {
    allowed_start_rules,
    cache,
    optimize,
    output,
    trace,
    features,
    header,
    parser,
    actions,
    initializer,
    value_type,
    name_prefix,
    extra,
  }
}

///|
/// The `use(feature)` test of `generateJS`: enabled unless set to false.
pub fn[T] Options::use_feature(self : Options[T], feature : String) -> Bool {
  match self.features.get(feature) {
    Some(b) => b
    None => true
  }
}

///|
/// The resolved features record used by generated parsers.
pub fn[T] Options::runtime_features(self : Options[T]) -> @runtime.Features {
  {
    text: self.use_feature("text"),
    offset: self.use_feature("offset"),
    range: self.use_feature("range"),
    location: self.use_feature("location"),
    expected: self.use_feature("expected"),
    error: self.use_feature("error"),
    filename: self.use_feature("filename"),
    default_tracer: self.use_feature("DefaultTracer"),
  }
}

///|
/// Allowed start rules, defaulting to the grammar's first rule.
pub fn[T] Options::start_rules(
  self : Options[T],
  grammar : @ast.Grammar,
) -> Array[String] {
  match self.allowed_start_rules {
    Some(rules) => rules
    None => [grammar.rules[0].name]
  }
}

///|
pub fn ParserOptions::copy(self : ParserOptions) -> ParserOptions {
  {
    reserved_words: self.reserved_words.map(words => words.copy()),
    extract_comments: self.extract_comments,
    filename: self.filename,
  }
}

///|
/// A copy that can be modified without affecting `self` (like PEG.js'
/// `processOptions`, which builds a fresh options object).
pub fn[T] Options::copy(self : Options[T]) -> Options[T] {
  {
    allowed_start_rules: self.allowed_start_rules.map(rules => rules.copy()),
    cache: self.cache,
    optimize: self.optimize,
    output: self.output,
    trace: self.trace,
    features: self.features.copy(),
    header: self.header.copy(),
    parser: self.parser.copy(),
    actions: self.actions.copy(),
    initializer: self.initializer,
    value_type: self.value_type,
    name_prefix: self.name_prefix,
    extra: self.extra.copy(),
  }
}
