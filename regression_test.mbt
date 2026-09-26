// Regressions found in review (cases the differential corpus does not reach).

///|
test "options can be reused across generate calls" {
  let options : @peg.Options[Unit] = @peg.Options::new()
  let first = @peg.generate("first = 'a'", options~)
  let second = @peg.generate("second = 'b'", options~)
  assert_true(first.parse("a") is Str("a"))
  assert_true(second.parse("b") is Str("b"))
  assert_true(options.allowed_start_rules is None)
  @peg.generate_source("third = 'c'", options~) |> ignore
  assert_true(options.output == Parser)
  assert_true(options.parser.reserved_words is None)
}

///|
test "classes with line continuations follow the generated regexp" {
  fn accepts(grammar : String, input : String) -> Bool raise {
    let parser : @peg.Parser[Unit] = @peg.generate(grammar)
    try parser.parse(input) catch {
      _ => false
    } noraise {
      _ => true
    }
  }

  // `[a-\<newline>]` is the regexp class `[a-]`.
  let g1 = "start = [a-\\\n]"
  assert_eq([accepts(g1, "a"), accepts(g1, "-"), accepts(g1, "b")], [
    true, true, false,
  ])
  // `[\<newline>-a]` is `[-a]`.
  let g2 = "start = [\\\n-a]"
  assert_eq([accepts(g2, "a"), accepts(g2, "-"), accepts(g2, "0")], [
    true, true, false,
  ])
  // `[a\<newline>-z]`... the bare dash joins neighbouring parts: `[b-d]` is
  // written as parts `b`, `["", "d"]`, which is the regexp `[b-d]`.
  let g3 = "start = [b\\\n-d]"
  assert_eq([accepts(g3, "b"), accepts(g3, "c"), accepts(g3, "-")], [
    true, true, false,
  ])
}

///|
test "a pass can replace the passes of a later stage" {
  let plugin : @peg.Plugin[Unit] = (session, _) => {
    session.passes.check.push({
      name: "replaceTransform",
      run: (_, session, _) => {
        session.passes.transform = [
          {
            name: "rewriteLiteral",
            run: (grammar, _, _) => {
              grammar.rules[0].expression.kind = Literal(
                value="b",
                ignore_case=false,
              )
            },
          },
        ]
      },
    })
  }
  let parser = @peg.generate("start = 'a'", plugins=[plugin])
  assert_true(parser.parse("b") is Str("b"))
}

///|
test "initializer bindings take precedence over static bindings" {
  let parser : @peg.Parser[Unit] = @peg.generate(
    "{ init }\nstart = 'a' { act }",
    options=@peg.Options::new(actions={ "#0": _ => Num(1.0) }, initializer=_ => {
      "act": _ => Num(2.0),
    }),
  )
  assert_true(parser.parse("a") is Num(2.0))
}
