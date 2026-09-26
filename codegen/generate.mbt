// MoonBit source generation (the counterpart of PEG.js' generate-js.js).
//
// A generated file belongs to a package importing "dii/peg/runtime" and
// "dii/peg/vm" (plus "dii/peg/bytecode" with optimize = size). Grammar code
// blocks contain MoonBit:
//
// * actions `{ ... }` are function bodies returning `PegValue`, with the
//   labels in scope as `PegValue` parameters;
// * predicates `&{ ... }` / `!{ ... }` return `Bool` or `PegValue` (judged
//   by JavaScript truthiness);
// * the initializer runs once per parse; its local definitions are visible
//   to all code blocks;
// * `ctx : @runtime.ActionContext` gives access to `ctx.text()`,
//   `ctx.location()`, `ctx.error(...)`, `ctx.expected(...)`, `ctx.options()`...
//
// Top-level generated names start with `peg_` / `Peg`.

///|
/// Placeholder for the value-name prefix in generated templates.
let value_mark : String = "\u{E000}"

///|
/// Placeholder for the type-name prefix in generated templates.
let type_mark : String = "\u{E001}"

///|
/// The type-name form of a name prefix: `"calc_"` -> `"Calc_"`.
fn type_prefix(prefix : String) -> String {
  if prefix == "" {
    return ""
  }
  let c = prefix.code_unit_at(0).to_int()
  let first = if c >= 'a' && c <= 'z' { c - 32 } else { c }
  first.unsafe_to_char().to_string() +
  prefix.unsafe_substring(start=1, end=prefix.length())
}

///|
/// Version of this port, recorded in generated files.
pub let version : String = "0.1.0"

///|
let moonbit_keywords : Array[String] = [
  "and", "as", "async", "break", "catch", "const", "continue", "declare", "defer",
  "derive", "else", "enum", "enumview", "extern", "false", "fn", "fnalias", "for",
  "guard", "if", "impl", "import", "in", "is", "let", "letrec", "lexmatch", "loop",
  "match", "mut", "noraise", "priv", "pub", "raise", "readonly", "return", "struct",
  "suberror", "test", "throw", "trait", "traitalias", "true", "try", "type", "typealias",
  "using", "where", "while", "with",
]

///|
/// Words that cannot be used as labels in grammars compiled to MoonBit.
pub fn reserved_words() -> Array[String] {
  moonbit_keywords.copy()
}

///|
/// Whether `name` can be a MoonBit parameter name.
pub fn is_valid_label(name : String) -> Bool {
  if name == "" || name == "_" || moonbit_keywords.contains(name) {
    return false
  }
  for i in 0..<name.length() {
    let c = name.code_unit_at(i).to_int()
    let ok = (c >= 'a' && c <= 'z') ||
      c == '_' ||
      (i > 0 && ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
    if !ok {
      return false
    }
  }
  true
}

///|
fn[T] check_labels(
  grammar : @ast.Grammar,
  session : @compiler.Session[T],
) -> Unit raise {
  fn visit(node : @ast.Node) -> Unit raise {
    if node.kind is Labeled(_, label=Some(label), ..) && !is_valid_label(label) {
      session.report_error(
        "Label \"\{label}\" is not a valid MoonBit identifier.",
        location=node.location,
      )
    }
    for child in node.children() {
      visit(child)
    }
  }

  for rule in grammar.rules {
    visit(rule.expression)
  }
}

///|
fn program_literal(program : @bytecode.Program) -> String {
  let lines = []
  lines.push("{")
  lines.push(
    "  opcodes: " +
    (if program.opcodes == @bytecode.default_opcodes {
      "@bytecode.default_opcodes"
    } else {
      opcodes_literal(program.opcodes)
    }) +
    ",",
  )
  lines.push("  rules: [")
  for rule in program.rules {
    lines.push(
      "    { name: \{string_literal(rule.name)}, bytecode: \{int_array_literal(rule.bytecode)} },",
    )
  }
  lines.push("  ],")
  lines.push(
    "  literals: [" + program.literals.map(string_literal).join(", ") + "],",
  )
  lines.push("  classes: [")
  for c in program.classes {
    lines.push(
      "    { parts: \{class_parts_literal(c.parts)}, inverted: \{bool_literal(c.inverted)}, ignore_case: \{bool_literal(c.ignore_case)} },",
    )
  }
  lines.push("  ],")
  lines.push("  expectations: [")
  for e in program.expectations {
    lines.push("    \{expectation_literal(e)},")
  }
  lines.push("  ],")
  lines.push("  functions: [")
  for f in program.functions {
    lines.push(
      "    { predicate: \{bool_literal(f.predicate)}, params: [\{f.params.map(string_literal).join(", ")}], body: \{string_literal(f.body)} },",
    )
  }
  lines.push("  ],")
  lines.push(
    "  initializer: " +
    (match program.initializer {
      Some(code) => "Some(" + string_literal(code) + ")"
      None => "None"
    }) +
    ",",
  )
  lines.push(
    "  allowed_start_rules: [" +
    program.allowed_start_rules.map(string_literal).join(", ") +
    "],",
  )
  lines.push("  cache: \{bool_literal(program.cache)},")
  lines.push("  trace: \{bool_literal(program.trace)},")
  lines.push("  features: " + features_literal(program.features) + ",")
  lines.push("}")
  lines.join("\n")
}

///|
fn features_literal(f : @runtime.Features) -> String {
  "{ text: \{bool_literal(f.text)}, offset: \{bool_literal(f.offset)}, range: \{bool_literal(f.range)}, location: \{bool_literal(f.location)}, expected: \{bool_literal(f.expected)}, error: \{bool_literal(f.error)}, filename: \{bool_literal(f.filename)}, default_tracer: \{bool_literal(f.default_tracer)} }"
}

///|
/// The per-parse factory: runs the initializer and builds the code block
/// closures.
fn actions_factory(program : @bytecode.Program, value_type : String) -> String {
  let lines = []
  lines.push("///|")
  lines.push("priv struct \u{E001}PegActions {")
  for i, f in program.functions {
    let params = f.params.map(_ => "\u{E001}PegValue").join(", ")
    let result = if f.predicate { "Bool" } else { "\u{E001}PegValue" }
    lines.push("  f\{i} : (\{params}) -> \{result} raise")
  }
  lines.push("}")
  lines.push("")
  lines.push("///|")
  lines.push(
    "/// Runs the grammar initializer and creates the code blocks of one parse.",
  )
  lines.push(
    "#warnings(\"-unused_value-unused_error_type-unused_mut-unused_try\")",
  )
  lines.push(
    "fn \u{E000}peg_actions(ctx : @runtime.ActionContext[\{value_type}]) -> \u{E001}PegActions raise {",
  )
  if program.initializer is Some(code) {
    lines.push(code)
  }
  lines.push("  \u{E001}PegActions::{")
  for i, f in program.functions {
    let params = f.params.map(p => p + " : \u{E001}PegValue").join(", ")
    if f.predicate {
      lines.push(
        "    f\{i}: fn(\{params}) -> Bool raise { @runtime.truthy((fn() raise {\{f.body}\n})()) },",
      )
    } else {
      lines.push(
        "    f\{i}: fn(\{params}) -> \u{E001}PegValue raise {\{f.body}\n},",
      )
    }
  }
  lines.push("  }")
  lines.push("}")
  lines.join("\n")
}

///|
fn speed_parser(
  program : @bytecode.Program,
  value_type : String,
) -> String raise {
  let lines = []
  for i, lit in program.literals {
    lines.push("///|")
    lines.push("let \u{E000}peg_c\{i} : String = \{string_literal(lit)}")
    lines.push("")
  }
  for i, c in program.classes {
    lines.push("///|")
    lines.push(
      "let \u{E000}peg_r\{i} : @runtime.ClassMatcher = @runtime.ClassMatcher::new(\{class_parts_literal(c.parts)}, inverted=\{bool_literal(c.inverted)}, ignore_case=\{bool_literal(c.ignore_case)})",
    )
    lines.push("")
  }
  for i, e in program.expectations {
    lines.push("///|")
    lines.push(
      "let \u{E000}peg_e\{i} : @runtime.Expectation = \{expectation_literal(e)}",
    )
    lines.push("")
  }
  lines.push("///|")
  lines.push("priv struct \u{E001}PegParser {")
  lines.push("  state : @runtime.State[\{value_type}]")
  lines.push("  actions : \u{E001}PegActions")
  lines.push("}")
  lines.push("")
  for i in 0..<program.rules.length() {
    lines.push(rule_function(program, i))
    lines.push("")
  }
  lines.push("///|")
  lines.push(
    "let \u{E000}peg_parser : @vm.Parser[\{value_type}] = @vm.Parser::from_fn((",
  )
  lines.push("  input,")
  lines.push("  options,")
  lines.push("  tracer,")
  lines.push(") => @runtime.drive(")
  lines.push("  input,")
  lines.push("  options,")
  lines.push("  tracer,")
  lines.push(
    "  allowed_start_rules=[\{program.allowed_start_rules.map(string_literal).join(", ")}],",
  )
  lines.push("  trace=\{bool_literal(program.trace)},")
  lines.push("  features=" + features_literal(program.features) + ",")
  lines.push("  run=(state, start) => {")
  lines.push(
    "    let p = { state, actions: \u{E000}peg_actions(@runtime.ActionContext::new(state, [][:], [][:])) }",
  )
  lines.push("    state.begin()")
  lines.push("    match start {")
  for name in program.allowed_start_rules {
    let index = program.rule_index(name).unwrap()
    lines.push("      \{string_literal(name)} => \u{E000}peg_parse_\{index}(p)")
  }
  lines.push("      _ => abort(\"unreachable\")")
  lines.push("    }")
  lines.push("  },")
  lines.push("))")
  lines.join("\n")
}

///|
fn size_parser(program : @bytecode.Program, value_type : String) -> String {
  let lines = []
  lines.push("///|")
  lines.push(
    "let \u{E000}peg_program : @bytecode.Program = \{program_literal(program)}",
  )
  lines.push("")
  lines.push("///|")
  lines.push(
    "let \u{E000}peg_parser : @vm.Parser[\{value_type}] = @vm.Parser::from_program(",
  )
  lines.push("  \u{E000}peg_program,")
  lines.push("  initializer=ctx => {")
  lines.push("    let a = \u{E000}peg_actions(ctx)")
  lines.push("    {")
  for i, f in program.functions {
    let args = []
    for j in 0..<f.params.length() {
      args.push("c.args[\{j}]")
    }
    let call = "(a.f\{i})(" + args.join(", ") + ")"
    if f.predicate {
      lines.push("      \"#\{i}\": c => Bool(\{call}),")
    } else {
      lines.push("      \"#\{i}\": c => \{call},")
    }
  }
  lines.push("    }")
  lines.push("  },")
  lines.push(") catch {")
  lines.push("  e => abort(\"invalid generated parser: \\{e}\")")
  lines.push("}")
  lines.join("\n")
}

///|
/// Generates the MoonBit source of a parser for `program`.
///
/// `name_prefix` is prepended to every generated top-level value name
/// (`parse`, `peg_*`) and, capitalized, to type names (`PegValue`...), so
/// several parsers can live in one package.
pub fn generate_source(
  program : @bytecode.Program,
  size? : Bool = false,
  value_type? : String = "Unit",
  header? : Array[String] = [],
  name_prefix? : String = "",
) -> String raise {
  let parts = []
  let head = [
    "// Generated by peg.mbt \{version} (a MoonBit port of PEG.js 0.11.0).",
    "// Requires in moon.pkg: \"dii/peg/runtime\", \"dii/peg/vm\"" +
    (if size { ", \"dii/peg/bytecode\"" } else { "" }) +
    ".",
  ]
  for line in header {
    for l in line.split("\n") {
      head.push("// " + l.to_owned())
    }
  }
  parts.push(head.join("\n"))
  parts.push(
    "///|\n/// Values produced by the parser.\npub type \u{E001}PegValue = @runtime.Value[\{value_type}]",
  )
  parts.push("///|\ntype \u{E001}PegSlot = @runtime.Slot[\{value_type}]")
  parts.push(actions_factory(program, value_type))
  parts.push(
    if size {
      size_parser(program, value_type)
    } else {
      speed_parser(program, value_type)
    },
  )
  parts.push(
    (
      $|///|
      $|/// Parses `input` from `start_rule` (default: the first allowed start
      $|/// rule). `options` is exposed to code blocks through `ctx.options()`.
      $|/// Raises `@runtime.SyntaxError` if the input does not match.
      $|pub fn \{value_mark}parse(
      $|  input : String,
      $|  start_rule? : String,
      $|  filename? : String,
      $|  tracer? : @runtime.Tracer[\{value_type}],
      $|  options? : Map[String, \{type_mark}PegValue],
      $|) -> \{type_mark}PegValue raise {
      $|  \{value_mark}peg_parser.parse(input, start_rule?, filename?, tracer?, options?)
      $|}
    ),
  )
  (parts.join("\n\n") + "\n")
  .replace_all(old=value_mark, new=name_prefix)
  .replace_all(old=type_mark, new=type_prefix(name_prefix))
}

///|
/// The `generateMoonBit` pass: when `options.output` is `Source`, stores the
/// generated MoonBit source in `grammar.code`.
pub fn[T] generate_moonbit(
  grammar : @ast.Grammar,
  session : @compiler.Session[T],
  options : @compiler.Options[T],
) -> Unit raise {
  if options.output != Source {
    return
  }
  check_labels(grammar, session)
  let program = @compiler.program_of(grammar, session, options)
  grammar.code = Some(
    generate_source(
      program,
      size=options.optimize == Size,
      value_type=options.value_type,
      header=options.header,
      name_prefix=options.name_prefix,
    ),
  )
}

///|
fn opcodes_literal(o : @bytecode.Opcodes) -> String {
  let fields = [
    ("push_empty_string", o.push_empty_string),
    ("push_undefined", o.push_undefined),
    ("push_null", o.push_null),
    ("push_failed", o.push_failed),
    ("push_empty_array", o.push_empty_array),
    ("push_curr_pos", o.push_curr_pos),
    ("pop", o.pop),
    ("pop_curr_pos", o.pop_curr_pos),
    ("pop_n", o.pop_n),
    ("nip", o.nip),
    ("append", o.append),
    ("wrap", o.wrap),
    ("text", o.text),
    ("pluck", o.pluck),
    ("if_", o.if_),
    ("if_error", o.if_error),
    ("if_not_error", o.if_not_error),
    ("while_not_error", o.while_not_error),
    ("match_any", o.match_any),
    ("match_string", o.match_string),
    ("match_string_ic", o.match_string_ic),
    ("match_class", o.match_class),
    ("accept_n", o.accept_n),
    ("accept_string", o.accept_string),
    ("expect", o.expect),
    ("load_saved_pos", o.load_saved_pos),
    ("update_saved_pos", o.update_saved_pos),
    ("call", o.call),
    ("rule", o.rule),
    ("silent_fails_on", o.silent_fails_on),
    ("silent_fails_off", o.silent_fails_off),
    ("expect_ns_begin", o.expect_ns_begin),
    ("expect_ns_end", o.expect_ns_end),
  ]
  "{ " + fields.map(f => "\{f.0}: \{f.1}").join(", ") + " }"
}
