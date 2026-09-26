///|
/// The root of a parsed grammar. Code-generation passes fill in the constant
/// tables and `code`.
pub(all) struct Grammar {
  mut initializer : Initializer?
  mut rules : Array[Rule]
  /// Comments keyed by start offset, in source order; `None` unless the
  /// `extractComments` option was set.
  mut comments : Array[(Int, Comment)]?
  location : Location
  mut literals : Array[String]?
  mut classes : Array[@bytecode.ClassConst]?
  mut expectations : Array[@runtime.Expectation]?
  mut functions : Array[@bytecode.FunctionConst]?
  /// Generated source code (set by the code generation pass).
  mut code : String?
} derive(Debug)

///|
pub fn Grammar::new(
  initializer : Initializer?,
  rules : Array[Rule],
  comments : Array[(Int, Comment)]?,
  location : Location,
) -> Grammar {
  {
    initializer,
    rules,
    comments,
    location,
    literals: None,
    classes: None,
    expectations: None,
    functions: None,
    code: None,
  }
}

///|
pub fn Grammar::find_rule(self : Grammar, name : String) -> Rule? {
  for rule in self.rules {
    if rule.name == name {
      return Some(rule)
    }
  }
  None
}

///|
/// Index of the rule named `name`, or -1.
pub fn Grammar::index_of_rule(self : Grammar, name : String) -> Int {
  for i, rule in self.rules {
    if rule.name == name {
      return i
    }
  }
  -1
}

///|
/// Whether `node` always consumes input when it succeeds (`Grammar.js`).
pub fn Grammar::always_consumes_on_success(self : Grammar, node : Node) -> Bool {
  match node.kind {
    Choice(alternatives) =>
      alternatives.iter().all(a => self.always_consumes_on_success(a))
    Sequence(elements) =>
      elements.iter().any(e => self.always_consumes_on_success(e))
    RuleRef(name~) =>
      match self.find_rule(name) {
        Some(rule) => self.always_consumes_on_success(rule.expression)
        // PEG.js would throw on the missing rule; undefined-rule reporting
        // runs first, so this is unreachable with the standard passes.
        None => abort("Rule \"\{name}\" is not defined")
      }
    Literal(value~, ..) => value != ""
    Named(e, ..)
    | Action(e, ..)
    | Labeled(e, ..)
    | Text(e)
    | OneOrMore(e)
    | Group(e) => self.always_consumes_on_success(e)
    SimpleAnd(_)
    | SimpleNot(_)
    | Optional(_)
    | ZeroOrMore(_)
    | SemanticAnd(..)
    | SemanticNot(..) => false
    Class(..) | Any => true
  }
}
