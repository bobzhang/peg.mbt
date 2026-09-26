///|
/// Result of `compile`: a parser or generated source, per `Options::output`.
pub(all) enum Compiled[T] {
  Parser(@vm.Parser[T])
  Source(String)
}

///|
/// Collects the bytecode program produced by the generate passes.
pub fn[T] program_of(
  grammar : @ast.Grammar,
  session : Session[T],
  options : Options[T],
) -> @bytecode.Program raise {
  guard grammar.literals is Some(literals) &&
    grammar.classes is Some(classes) &&
    grammar.expectations is Some(expectations) &&
    grammar.functions is Some(functions) else {
    raise CompilerError("The grammar has not been compiled to bytecode.")
  }
  let rules = []
  for rule in grammar.rules {
    guard rule.bytecode is Some(bytecode) else {
      raise CompilerError("Rule \"\{rule.name}\" has no bytecode.")
    }
    rules.push(@bytecode.RuleCode::{ name: rule.name, bytecode, })
  }
  {
    opcodes: session.opcodes,
    rules,
    literals,
    classes,
    expectations,
    functions,
    initializer: grammar.initializer.map(i => i.code),
    allowed_start_rules: options.start_rules(grammar),
    cache: options.cache,
    trace: options.trace,
    features: options.runtime_features(),
  }
}

///|
/// The default backend: interprets the grammar's bytecode, implementing code
/// blocks with `Options::actions` / `Options::initializer`.
pub fn[T] interpreter_backend(
  grammar : @ast.Grammar,
  session : Session[T],
  options : Options[T],
) -> @vm.Parser[T] raise {
  @vm.Parser::from_program(
    program_of(grammar, session, options),
    actions=options.actions,
    initializer?=options.initializer,
  )
}

///|
/// Runs the session's passes over `grammar` and produces the output selected
/// by `options.output` (`peg.compiler.compile`).
///
/// Raises `GrammarError` / `CompilerError` for semantic errors.
pub fn[T] compile(
  grammar : @ast.Grammar,
  session : Session[T],
  options : Options[T],
) -> Compiled[T] raise {
  // Resolve defaults on a copy, leaving the caller's options untouched.
  let options = options.copy()
  options.allowed_start_rules = Some(options.start_rules(grammar))
  // Each stage is looked up when it starts, so a pass may replace the
  // passes of later stages.
  for pass in session.passes.check.copy() {
    (pass.run)(grammar, session, options)
  }
  for pass in session.passes.transform.copy() {
    (pass.run)(grammar, session, options)
  }
  for pass in session.passes.generate.copy() {
    (pass.run)(grammar, session, options)
  }
  match options.output {
    Parser => Parser((session.backend)(grammar, session, options))
    Source =>
      match grammar.code {
        Some(code) => Source(code)
        None => raise CompilerError("No source code was generated.")
      }
  }
}
