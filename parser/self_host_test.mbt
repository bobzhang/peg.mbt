///|
/// Our own compiler, applied to PEG.js' grammar (`src/parser.pegjs`) with the
/// options used to build the frozen meta parser, must reproduce its program.
test "compiler reproduces the frozen meta-grammar program" {
  let grammar = @parser.parse(@parser.meta_grammar_source)
  let session : @compiler.Session[Unit] = @compiler.Session::new(parser=(
    input,
    _,
  ) => @parser.parse(input))
  let options : @compiler.Options[Unit] = @compiler.Options::new(features={
    "offset": false,
    "range": false,
    "expected": false,
  })
  let captured : Ref[@bytecode.Program?] = Ref(None)
  session.backend = (grammar, session, options) => {
    captured.val = Some(@compiler.program_of(grammar, session, options))
    @vm.Parser::from_fn((_, _, _) => Undefined)
  }
  @compiler.compile(grammar, session, options) |> ignore
  let program = captured.val.unwrap()
  let frozen = @parser.meta_program_for_testing()
  assert_eq(program.literals, frozen.literals)
  assert_eq(program.classes, frozen.classes)
  assert_eq(program.expectations, frozen.expectations)
  assert_eq(program.functions, frozen.functions)
  assert_eq(program.rules, frozen.rules)
  assert_eq(program.initializer, frozen.initializer)
  assert_eq(program.features, frozen.features)
}
