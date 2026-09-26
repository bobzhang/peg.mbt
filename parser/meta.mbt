// The PEG.js grammar parser: the frozen bytecode of `src/parser.pegjs`
// (see meta_program.mbt) run by the VM, with the grammar's JavaScript
// actions translated to MoonBit below.

///|
/// Values built by the meta-grammar's actions.
priv enum Meta {
  N(@ast.Node)
  R(@ast.Rule)
  I(@ast.Initializer)
  G(@ast.Grammar)
}

///|
type MValue = @runtime.Value[Meta]

///|
type Ctx = @runtime.ActionContext[Meta]

///|
/// JavaScript (ECMA-262 5th ed. strict mode) reserved words: the default
/// words that cannot be used as labels (`util.reservedWords`).
pub let js_reserved_words : ReadOnlyArray[String] = [
  "break", "case", "catch", "continue", "debugger", "default", "delete", "do", "else",
  "finally", "for", "function", "if", "in", "instanceof", "new", "return", "switch",
  "this", "throw", "try", "typeof", "var", "void", "while", "with", "class", "const",
  "enum", "export", "extends", "implements", "import", "interface", "let", "package",
  "private", "protected", "public", "static", "super", "yield", "false", "null",
  "true",
]

///|
fn node_of(v : MValue) -> @ast.Node {
  match v {
    Custom(N(n)) => n
    _ => abort("meta parser: expected an AST node")
  }
}

///|
fn str_of(v : MValue) -> String {
  match v {
    Str(s) => s
    _ => abort("meta parser: expected a string")
  }
}

///|
fn arr_of(v : MValue) -> Array[MValue] {
  match v {
    Arr(xs) => xs
    _ => abort("meta parser: expected an array")
  }
}

///|
fn node_value(ctx : Ctx, kind : @ast.Kind) -> MValue raise {
  Custom(N(@ast.Node::new(kind, ctx.location())))
}

///|
fn joined(xs : Array[MValue]) -> String {
  let sb = StringBuilder()
  for x in xs {
    sb.write_string(str_of(x))
  }
  sb.to_string()
}

///|
/// The grammar's initializer: sets up the reserved words and comment table
/// for one parse and returns the action implementations, indexed like
/// `meta_program.functions`.
fn meta_actions(init : Ctx) -> Array[@runtime.ActionFn[Meta]] {
  let options = init.options()
  let reserved : Map[String, Bool] = Map([])
  let words : Array[String] = match options.get("reservedWords") {
    Some(Arr(xs)) =>
      xs.filter_map(x => {
        match x {
          Str(s) => Some(s)
          _ => None
        }
      })
    Some(v) if v.truthy() => []
    _ => [..js_reserved_words]
  }
  for w in words {
    if w != "__proto__" {
      reserved[w] = true
    }
  }
  let extract_comments = match options.get("extractComments") {
    Some(v) => v.truthy()
    None => false
  }
  let comments : Map[Int, @ast.Comment] = Map([])
  fn add_comment(ctx : Ctx, text : String, multiline : Bool) -> MValue raise {
    if extract_comments {
      let location = ctx.location()
      comments[location.start.offset] = { text, multiline, location, }
    }
    Str(text)
  }

  fn escape(s : String) -> @runtime.ActionFn[Meta] {
    _ => Str(s)
  }

  let actions : Array[@runtime.ActionFn[Meta]] = [
    // 0: Grammar
    ctx => {
      let initializer = match ctx.args[0] {
        Custom(I(i)) => Some(i)
        _ => None
      }
      let rules = arr_of(ctx.args[1]).map(r => {
        match r {
          Custom(R(rule)) => rule
          _ => abort("meta parser: expected a rule")
        }
      })
      let comment_list = if extract_comments {
        let sorted = comments.to_array()
        sorted.sort_by_key(c => c.0)
        Some(sorted)
      } else {
        None
      }
      Custom(
        G(@ast.Grammar::new(initializer, rules, comment_list, ctx.location())),
      )
    },
    // 1: Initializer
    ctx => Custom(I({ code: str_of(ctx.args[0]), location: ctx.location(), })),
    // 2: Rule
    ctx => {
      let name = str_of(ctx.args[0])
      let display_name = ctx.args[1]
      let mut expression = node_of(ctx.args[2])
      if display_name.truthy() {
        expression = @ast.Node::new(
          Named(name=str_of(display_name), expression),
          ctx.location(),
        )
      }
      Custom(R(@ast.Rule::new(name, expression, ctx.location())))
    },
    // 3: ChoiceExpression
    ctx => {
      let tail = arr_of(ctx.args[1])
      if tail.is_empty() {
        return ctx.args[0]
      }
      node_value(ctx, Choice([node_of(ctx.args[0]), ..tail.map(node_of)]))
    },
    // 4: ActionExpression
    ctx => {
      match ctx.args[1] {
        Null => ctx.args[0]
        code => node_value(ctx, Action(node_of(ctx.args[0]), code=str_of(code)))
      }
    },
    // 5: SequenceExpression
    ctx => {
      let head = node_of(ctx.args[0])
      let tail = arr_of(ctx.args[1])
      if tail.is_empty() && !(head.kind is Labeled(_, pick=true, ..)) {
        return ctx.args[0]
      }
      node_value(ctx, Sequence([head, ..tail.map(node_of)]))
    },
    // 6: LabeledExpression (plucked)
    ctx => {
      let label = match ctx.args[0] {
        Null => None
        l => Some(str_of(l))
      }
      node_value(ctx, Labeled(label~, pick=true, node_of(ctx.args[1])))
    },
    // 7: LabeledExpression
    ctx => {
      node_value(
        ctx,
        Labeled(
          label=Some(str_of(ctx.args[0])),
          pick=false,
          node_of(ctx.args[1]),
        ),
      )
    },
    // 8: LabelIdentifier
    ctx => {
      let name = str_of(ctx.args[0])
      if reserved.contains(name) {
        ctx.error(
          "Label can't be a reserved word \"\{name}\".",
          location=ctx.location(),
        )
      }
      Str(name)
    },
    // 9: PrefixedExpression
    ctx => {
      let expression = node_of(ctx.args[1])
      node_value(
        ctx,
        match str_of(ctx.args[0]) {
          "text" => Text(expression)
          "simple_and" => SimpleAnd(expression)
          _ => SimpleNot(expression)
        },
      )
    },
    escape("text"),
    escape("simple_and"),
    escape("simple_not"),
    // 13: SuffixedExpression
    ctx => {
      let expression = node_of(ctx.args[0])
      node_value(
        ctx,
        match str_of(ctx.args[1]) {
          "optional" => Optional(expression)
          "zero_or_more" => ZeroOrMore(expression)
          _ => OneOrMore(expression)
        },
      )
    },
    escape("optional"),
    escape("zero_or_more"),
    escape("one_or_more"),
    // 17: parenthesized expression
    ctx => {
      let e = node_of(ctx.args[0])
      match e.kind {
        Labeled(_, ..) | Sequence(_) => node_value(ctx, Group(e))
        _ => ctx.args[0]
      }
    },
    // 18: RuleReferenceExpression
    ctx => node_value(ctx, RuleRef(name=str_of(ctx.args[0]))),
    // 19: SemanticPredicateExpression
    ctx => {
      let code = str_of(ctx.args[1])
      node_value(
        ctx,
        match str_of(ctx.args[0]) {
          "semantic_and" => SemanticAnd(code~)
          _ => SemanticNot(code~)
        },
      )
    },
    escape("semantic_and"),
    escape("semantic_not"),
    // 22: MultiLineComment(NoLineTerminator)
    ctx => add_comment(ctx, str_of(ctx.args[0]), true),
    // 23: SingleLineComment
    ctx => add_comment(ctx, str_of(ctx.args[0]), false),
    // 24: Identifier
    ctx => Str(str_of(ctx.args[0]) + joined(arr_of(ctx.args[1]))),
    // 25: LiteralMatcher
    ctx => {
      node_value(
        ctx,
        Literal(value=str_of(ctx.args[0]), ignore_case=!(ctx.args[1] is Null)),
      )
    },
    // 26: StringLiteral
    ctx => Str(joined(arr_of(ctx.args[0]))),
    // 27: CharacterClassMatcher
    ctx => {
      let parts = arr_of(ctx.args[1]).filter_map(part => {
        match part {
          Str("") => None
          Str(c) => Some(@runtime.ClassPart::Char(c))
          Arr([Str(a), Str(b)]) => Some(Range(a, b))
          _ => abort("meta parser: bad class part")
        }
      })
      node_value(
        ctx,
        Class(
          parts~,
          inverted=!(ctx.args[0] is Null),
          ignore_case=!(ctx.args[2] is Null),
        ),
      )
    },
    // 28: ClassCharacterRange
    ctx => {
      let begin = str_of(ctx.args[0])
      let end = str_of(ctx.args[1])
      // `charCodeAt(0)` of "" is NaN, which compares false.
      if begin != "" && end != "" && begin.code_unit_at(0) > end.code_unit_at(0) {
        ctx.error("Invalid character range: " + ctx.text() + ".")
      }
      Arr([Str(begin), Str(end)])
    },
    escape(""),
    escape("\u{0}"),
    escape("\u{8}"),
    escape("\u{c}"),
    escape("\n"),
    escape("\r"),
    escape("\t"),
    escape("\u{b}"),
    // 37: HexEscapeSequence / UnicodeEscapeSequence
    ctx => {
      let digits = str_of(ctx.args[0])
      let mut code = 0
      for i in 0..<digits.length() {
        let c = digits.code_unit_at(i).to_int()
        let d = if c >= '0' && c <= '9' {
          c - '0'
        } else if c >= 'a' && c <= 'f' {
          c - 'a' + 10
        } else {
          c - 'A' + 10
        }
        code = code * 16 + d
      }
      Str(@runtime.string_of_code_units([code]))
    },
    // 38: AnyMatcher
    ctx => node_value(ctx, Any),
    // 39: CodeBlock without closing brace
    ctx => ctx.error("Unbalanced brace."),
  ]
  actions
}

///|
let meta_parser : @vm.Parser[Meta] = {
  let init : @runtime.InitFn[Meta] = ctx => {
    let actions = meta_actions(ctx)
    let bindings : Map[String, @runtime.ActionFn[Meta]] = Map([])
    for i, action in actions {
      bindings["#\{i}"] = action
    }
    bindings
  }
  @vm.Parser::from_program(meta_program, initializer=init) catch {
    e => abort("meta parser: \{e}")
  }
}

///|
/// Parses PEG.js grammar source into an AST (`peg.parser.parse`).
///
/// * `reserved_words`: words not allowed as labels (default:
///   `js_reserved_words`);
/// * `extract_comments`: collect comments into `Grammar::comments`;
/// * `filename`: recorded in every location.
///
/// Raises `@runtime.SyntaxError` on invalid grammar syntax.
pub fn parse(
  input : String,
  reserved_words? : Array[String],
  extract_comments? : Bool = false,
  filename? : String,
) -> @ast.Grammar raise {
  let options : Map[String, MValue] = Map([])
  if reserved_words is Some(words) {
    options["reservedWords"] = Arr(words.map(w => MValue::Str(w)))
  }
  options["extractComments"] = Bool(extract_comments)
  if filename is Some(f) {
    options["filename"] = Str(f)
  }
  match meta_parser.parse(input, options~) {
    Custom(G(grammar)) => grammar
    _ => abort("meta parser: expected a grammar")
  }
}
