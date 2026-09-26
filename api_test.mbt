// Ports of test/api/generated-parser-api.spec.js (tracing) and
// test/api/plugin-api.spec.js.

///|
fn trace_parser() -> Parser[Unit] raise {
  generate(
    (
      #|start = a / b
      #|a = 'a'
      #|b = 'b'
    ),
    options=Options::new(trace=true),
  )
}

///|
test "default tracer logs rule events" {
  let lines : Array[String] = []
  let parser = trace_parser()
  parser.parse("b", tracer=Tracer::default(log=line => lines.push(line)))
  |> ignore
  assert_eq(lines, [
    "1:1-1:1 rule.enter start", "1:1-1:1 rule.enter   a", "1:1-1:1 rule.fail    a",
    "1:1-1:1 rule.enter   b", "1:1-1:2 rule.match   b", "1:1-1:2 rule.match start",
  ])
}

///|
test "custom tracer receives tracing events" {
  let events : Array[Json] = []
  let parser = trace_parser()
  parser.parse("b", tracer={
    trace: event => {
      let obj : Map[String, Json] = {
        "type": event.type_.name().to_json(),
        "rule": event.rule.to_json(),
        "location": event.location.to_json(),
      }
      if event.result is Some(result) {
        obj["result"] = result.to_json_with(_ => Json::null())
      }
      events.push(Json::object(obj))
    },
  })
  |> ignore
  fn loc(start : Int, end : Int) -> Json {
    {
      "start": { "offset": start, "line": 1, "column": start + 1 },
      "end": { "offset": end, "line": 1, "column": end + 1 },
    }
  }

  let expected : Array[Json] = [
    { "type": "rule.enter", "rule": "start", "location": loc(0, 0) },
    { "type": "rule.enter", "rule": "a", "location": loc(0, 0) },
    { "type": "rule.fail", "rule": "a", "location": loc(0, 0) },
    { "type": "rule.enter", "rule": "b", "location": loc(0, 0) },
    { "type": "rule.match", "rule": "b", "result": "b", "location": loc(0, 1) },
    {
      "type": "rule.match",
      "rule": "start",
      "result": "b",
      "location": loc(0, 1),
    },
  ]
  assert_eq(events, expected)
}

///|
test "cached rules are traced on cache hits" {
  let names : Array[String] = []
  let parser : Parser[Unit] = generate(
    (
      #|start = a "x" / a "y"
      #|a = "a"
    ),
    options=Options::new(trace=true, cache=true),
  )
  parser.parse("ay", tracer={
    trace: event => names.push("\{event.type_.name()} \{event.rule}"),
  })
  |> ignore
  assert_eq(names, [
    "rule.enter start", "rule.enter a", "rule.match a", "rule.enter a", "rule.match a",
    "rule.match start",
  ])
}

///|
let plugin_grammar = "start = 'a'"

///|
test "plugin: use is called for each plugin" {
  let used = [false, false, false]
  let plugins : Array[Plugin[Unit]] = [
    (_, _) => used[0] = true,
    (_, _) => used[1] = true,
    (_, _) => used[2] = true,
  ]
  generate(plugin_grammar, plugins~) |> ignore
  assert_eq(used, [true, true, true])
}

///|
test "plugin: receives configuration" {
  let checked = Ref(false)
  let plugin : Plugin[Unit] = (session, _) => {
    let grammar = session.parse("start = 'a'", @compiler.ParserOptions::new())
    assert_eq(grammar.rules.length(), 1)
    assert_true(session.passes.check.length() > 0)
    assert_true(session.passes.transform.length() > 0)
    assert_true(session.passes.generate.length() > 0)
    checked.val = true
  }
  generate(plugin_grammar, plugins=[plugin]) |> ignore
  assert_true(checked.val)
}

///|
test "plugin: receives options" {
  let options : Options[Unit] = Options::new(extra={ "foo": 42 })
  let seen = Ref(false)
  let plugin : Plugin[Unit] = (_, received) => {
    assert_true(physical_equal(received, options))
    assert_eq(received.extra.get("foo"), Some(42))
    seen.val = true
  }
  generate(plugin_grammar, options~, plugins=[plugin]) |> ignore
  assert_true(seen.val)
}

///|
test "plugin: can replace parser" {
  // A generated parser that turns its whole input into a one-rule grammar
  // matching that input literally.
  let grammar_parser : Parser[@ast.Grammar] = generate(
    "start = .* { makeGrammar }",
    options=Options::new(actions={
      "makeGrammar": ctx => {
        let location = ctx.location()
        let literal = @ast.Node::new(
          Literal(value=ctx.text(), ignore_case=false),
          location,
        )
        Custom(
          @ast.Grammar::new(
            None,
            [@ast.Rule::new("start", literal, location)],
            None,
            location,
          ),
        )
      },
    }),
  )
  let plugin : Plugin[Unit] = (session, _) => {
    session.parser = (input, _) => {
      match grammar_parser.parse(input) {
        Custom(g) => g
        _ => fail("expected a grammar")
      }
    }
  }
  let parser = generate("a", plugins=[plugin])
  assert_true(parser.parse("a") is Str("a"))
}

///|
test "plugin: can change compiler passes" {
  let plugin : Plugin[Unit] = (session, _) => {
    session.passes.generate = []
    session.backend = (_, _, _) => @vm.Parser::from_fn((_, _, _) => Num(42.0))
  }
  let parser = generate(plugin_grammar, plugins=[plugin])
  assert_true(parser.parse("a") is Num(42.0))
}

///|
test "plugin: can change options" {
  let plugin : Plugin[Unit] = (_, options) => {
    options.allowed_start_rules = Some(["b", "c"])
  }
  let parser : Parser[Unit] = generate(
    (
      #|a = 'x'
      #|b = 'x'
      #|c = 'x'
    ),
    options=Options::new(allowed_start_rules=["a"]),
    plugins=[plugin],
  )
  let rejected = try parser.parse("x", start_rule="a") catch {
    @runtime.InvalidStartRule(_) => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(rejected)
  assert_true(parser.parse("x", start_rule="b") is Str("x"))
  assert_true(parser.parse("x", start_rule="c") is Str("x"))
}

///|
test "unbound code blocks are rejected at generate time" {
  let result = try generate("start = 'a' { nope }") catch {
    @vm.UnboundCode(kind~, code~) => "\{kind}: \{code}"
    e => "other: \{e}"
  } noraise {
    _ => "generated"
  }
  inspect(result, content="action:  nope ")
}
