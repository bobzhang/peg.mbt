///|
/// A character class constant (`classes[i]` of the abstract machine).
pub(all) struct ClassConst {
  parts : Array[@runtime.ClassPart]
  inverted : Bool
  ignore_case : Bool
} derive(Eq, Debug)

///|
pub impl ToJson for ClassConst with fn to_json(self) {
  {
    "value": self.parts.to_json(),
    "inverted": self.inverted.to_json(),
    "ignoreCase": self.ignore_case.to_json(),
  }
}

///|
/// An action, predicate or initializer code block (`functions[i]`).
/// Deduplicated on (predicate, params, body), exactly as PEG.js does.
pub(all) struct FunctionConst {
  predicate : Bool
  params : Array[String]
  body : String
} derive(Eq, Debug)

///|
pub impl ToJson for FunctionConst with fn to_json(self) {
  {
    "predicate": self.predicate.to_json(),
    "params": self.params.to_json(),
    "body": self.body.to_json(),
  }
}

///|
/// Serializes an expectation constant the way `generateBytecode` stores it
/// (`{type: "rule", value}` for named rules, `value` for literal text).
pub fn expectation_const_json(e : @runtime.Expectation) -> Json {
  match e {
    Other(description~) => { "type": "rule", "value": description.to_json() }
    Literal(text~, ignore_case~) =>
      {
        "type": "literal",
        "value": text.to_json(),
        "ignoreCase": ignore_case.to_json(),
      }
    Class(parts~, inverted~, ignore_case~) =>
      {
        "type": "class",
        "value": parts.to_json(),
        "inverted": inverted.to_json(),
        "ignoreCase": ignore_case.to_json(),
      }
    Any => { "type": "any" }
    End => { "type": "end" }
    Not(_) => abort("negated expectations are never constants")
  }
}

///|
/// The compiled form of one rule.
pub(all) struct RuleCode {
  name : String
  bytecode : Array[Int]
} derive(Eq, Debug)

///|
/// Everything the parsing machine needs: per-rule bytecode plus the constant
/// tables it indexes. Produced by the compiler, consumed by the VM and by the
/// code generator.
pub(all) struct Program {
  opcodes : Opcodes
  rules : Array[RuleCode]
  literals : Array[String]
  classes : Array[ClassConst]
  expectations : Array[@runtime.Expectation]
  functions : Array[FunctionConst]
  /// Initializer code block, if the grammar has one.
  initializer : String?
  /// Names of the rules parsing may start from; the first is the default.
  allowed_start_rules : Array[String]
  /// Whether rule results are memoized (the `cache` option).
  cache : Bool
  /// Whether rule enter/match/fail events are traced (the `trace` option).
  trace : Bool
  features : @runtime.Features
} derive(Debug)

///|
pub fn Program::rule_index(self : Program, name : String) -> Int? {
  for i, r in self.rules {
    if r.name == name {
      return Some(i)
    }
  }
  None
}

///|
pub extend ClassConst with ToJson::{to_json}

///|
pub extend FunctionConst with ToJson::{to_json}
