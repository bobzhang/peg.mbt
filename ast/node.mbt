///|
pub using @runtime {type Location, type Pos, type ClassPart}

///|
/// The kind-specific payload of an expression node.
pub(all) enum Kind {
  Named(name~ : String, Node)
  Choice(Array[Node])
  Action(Node, code~ : String)
  Sequence(Array[Node])
  /// `pick` distinguishes `@label:e` / `@e` (plucked) from `label:e`.
  Labeled(label~ : String?, pick~ : Bool, Node)
  Text(Node)
  SimpleAnd(Node)
  SimpleNot(Node)
  Optional(Node)
  ZeroOrMore(Node)
  OneOrMore(Node)
  Group(Node)
  SemanticAnd(code~ : String)
  SemanticNot(code~ : String)
  RuleRef(name~ : String)
  Literal(value~ : String, ignore_case~ : Bool)
  Class(parts~ : Array[ClassPart], inverted~ : Bool, ignore_case~ : Bool)
  Any
} derive(Debug)

///|
/// An expression node. Passes may rewrite `kind` in place and annotate
/// `match_result` (the `match` property of PEG.js nodes: -1 never matches,
/// 0 may match, 1 always matches).
pub(all) struct Node {
  mut kind : Kind
  location : Location
  mut match_result : Int?
} derive(Debug)

///|
pub fn Node::new(kind : Kind, location : Location) -> Node {
  { kind, location, match_result: None, }
}

///|
/// The PEG.js `type` string of this node.
pub fn Node::type_name(self : Node) -> String {
  match self.kind {
    Named(_, ..) => "named"
    Choice(_) => "choice"
    Action(_, ..) => "action"
    Sequence(_) => "sequence"
    Labeled(_, ..) => "labeled"
    Text(_) => "text"
    SimpleAnd(_) => "simple_and"
    SimpleNot(_) => "simple_not"
    Optional(_) => "optional"
    ZeroOrMore(_) => "zero_or_more"
    OneOrMore(_) => "one_or_more"
    Group(_) => "group"
    SemanticAnd(..) => "semantic_and"
    SemanticNot(..) => "semantic_not"
    RuleRef(..) => "rule_ref"
    Literal(..) => "literal"
    Class(..) => "class"
    Any => "any"
  }
}

///|
/// The single child expression of wrapper nodes (`expression` in PEG.js).
pub fn Node::expression(self : Node) -> Node? {
  match self.kind {
    Named(e, ..)
    | Action(e, ..)
    | Labeled(e, ..)
    | Text(e)
    | SimpleAnd(e)
    | SimpleNot(e)
    | Optional(e)
    | ZeroOrMore(e)
    | OneOrMore(e)
    | Group(e) => Some(e)
    _ => None
  }
}

///|
/// Direct child expressions, in order.
pub fn Node::children(self : Node) -> ArrayView[Node] {
  match self.kind {
    Choice(xs) | Sequence(xs) => xs[:]
    _ =>
      match self.expression() {
        Some(e) => [e][:]
        None => [][:]
      }
  }
}

///|
/// An `{ ... }` initializer block at the top of a grammar.
pub(all) struct Initializer {
  code : String
  location : Location
} derive(Debug)

///|
/// A grammar rule. Passes annotate `report_failures`, `match_result` and
/// `bytecode`.
pub(all) struct Rule {
  mut name : String
  mut expression : Node
  location : Location
  mut report_failures : Bool?
  mut match_result : Int?
  mut bytecode : Array[Int]?
} derive(Debug)

///|
pub fn Rule::new(name : String, expression : Node, location : Location) -> Rule {
  {
    name,
    expression,
    location,
    report_failures: None,
    match_result: None,
    bytecode: None,
  }
}

///|
/// A comment collected with the `extractComments` parser option.
pub(all) struct Comment {
  text : String
  multiline : Bool
  location : Location
} derive(Debug)
