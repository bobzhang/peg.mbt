// MoonBit implementations of the JavaScript code blocks used by the grammars
// of the upstream test suite, and the runner for generate_fixture_test.mbt.

///|
struct GenerateCase {
  grammar : String
  start : Array[String]?
  cache : Bool
  trace : Bool
  size : Bool
  expected : String
  parses : Array[(String, String, String)]
}

///|
type V = Value[Unit]

///|
type Ctx = ActionContext[Unit]

///|
/// Stands in for `throw 'Boom!'`.
suberror Thrown {
  Thrown(String)
}

///|
/// JavaScript `ToNumber`.
fn js_to_number(v : V) -> Double {
  match v {
    Undefined => @double.not_a_number
    Null => 0.0
    Bool(b) => if b { 1.0 } else { 0.0 }
    Num(n) => n
    Str(s) => {
      let t = s.trim().to_owned()
      if t == "" {
        0.0
      } else {
        @string.parse_double(t) catch {
          _ => @double.not_a_number
        }
      }
    }
    Arr(_) => js_to_number(Str(v.js_string()))
    Obj(_) | Custom(_) => @double.not_a_number
  }
}

///|
/// JavaScript binary `+`.
fn js_add(a : V, b : V) -> V {
  match (a, b) {
    (Num(x), Num(y)) => Num(x + y)
    (Str(_) | Arr(_) | Obj(_) | Custom(_), _)
    | (_, Str(_) | Arr(_) | Obj(_) | Custom(_)) =>
      Str(a.js_string() + b.js_string())
    _ => Num(js_to_number(a) + js_to_number(b))
  }
}

///|
/// JavaScript `Array.prototype.join`.
fn js_join(v : V, sep : String) -> V {
  match v {
    Arr(xs) =>
      Str(
        xs
        .map(x => {
          match x {
            Undefined | Null => ""
            _ => x.js_string()
          }
        })
        .join(sep),
      )
    _ => abort("join on a non-array")
  }
}

///|
/// JavaScript `===` on primitive values.
fn js_strict_equal(a : V, b : V) -> Bool {
  match (a, b) {
    (Undefined, Undefined) | (Null, Null) => true
    (Bool(x), Bool(y)) => x == y
    (Num(x), Num(y)) => x == y
    (Str(x), Str(y)) => x == y
    (Arr(x), Arr(y)) => physical_equal(x, y)
    (Obj(x), Obj(y)) => physical_equal(x, y)
    _ => false
  }
}

///|
fn fixed_location() -> Location {
  {
    filename: None,
    start: { offset: 1, line: 1, column: 2, },
    end: { offset: 2, line: 1, column: 3, },
  }
}

///|
fn reduce_arith(ctx : Ctx, plus : String, minus : String) -> V raise {
  let tail = ctx.label("tail").as_arr().unwrap()
  let mut result = ctx.label("head")
  for element in tail {
    let el = element.as_arr().unwrap()
    let x = js_to_number(result)
    let y = js_to_number(el[1])
    result = match el[0] {
      Str(op) if op == plus =>
        if plus == "+" {
          js_add(result, el[1])
        } else {
          Num(x * y)
        }
      Str(op) if op == minus =>
        if minus == "-" {
          Num(x - y)
        } else {
          Num(x / y)
        }
      _ => Undefined
    }
  }
  result
}

///|
/// Stateless code blocks, keyed by their (trimmed) JavaScript text.
fn label_action(name : String) -> ActionFn[Unit] {
  ctx => ctx.label(name)
}

///|
fn static_bindings() -> Map[String, ActionFn[Unit]] {
  let l = label_action
  {
    "return 'a';": _ => Str("a"),
    "return 'b';": _ => Str("b"),
    "return 'c';": _ => Str("c"),
    "return true;": _ => Bool(true),
    "return false;": _ => Bool(false),
    "return a === 'a';": ctx => Bool(js_strict_equal(ctx.label("a"), Str("a"))),
    "return b === undefined;": ctx => Bool(ctx.label("b") is Undefined),
    "return b === 'b';": ctx => Bool(js_strict_equal(ctx.label("b"), Str("b"))),
    "return a !== 'a';": ctx => Bool(!js_strict_equal(ctx.label("a"), Str("a"))),
    "return b !== undefined;": ctx => Bool(!(ctx.label("b") is Undefined)),
    "return b !== 'b';": ctx => Bool(!js_strict_equal(ctx.label("b"), Str("b"))),
    "return a;": l("a"),
    "return b;": l("b"),
    "return val;": l("val"),
    "return expr;": l("expr"),
    "return z;": l("z"),
    "return offset();": ctx => Num(ctx.offset().to_double()),
    "return range();": ctx => {
      let (s, e) = ctx.range()
      Arr([Num(s.to_double()), Num(e.to_double())])
    },
    "return n > 0;": ctx => Bool(js_to_number(ctx.label("n")) > 0.0),
    "return 42;": _ => Num(42.0),
    "return [a, b, c];": ctx => {
      Arr([ctx.label("a"), ctx.label("b"), ctx.label("c")])
    },
    "return options;": ctx => Obj(ctx.options()),
    "return text();": ctx => Str(ctx.text()),
    "expected('a');": ctx => ctx.expected("a"),
    "expected('a', {\n    start: { offset: 1, line: 1, column: 2 },\n    end: { offset: 2, line: 1, column: 3 }\n  });": ctx => {
      ctx.expected("a", location=fixed_location())
    },
    "error('a');": ctx => ctx.error("a"),
    "error('a', {\n    start: { offset: 1, line: 1, column: 2 },\n    end: { offset: 2, line: 1, column: 3 }\n  });": ctx => {
      ctx.error("a", location=fixed_location())
    },
    "throw 'Boom!';": _ => raise Thrown("Boom!"),
    "return tail.reduce(function(result, element) {\n          if (element[0] === '+') { return result + element[1]; }\n          if (element[0] === '-') { return result - element[1]; }\n        }, head);": ctx => {
      reduce_arith(ctx, "+", "-")
    },
    "return tail.reduce(function(result, element) {\n              if (element[0] === '*') { return result * element[1]; }\n              if (element[0] === '/') { return result / element[1]; }\n            }, head);": ctx => {
      reduce_arith(ctx, "*", "/")
    },
    "return parseInt(digits.join(''), 10);": ctx => {
      let s = js_join(ctx.label("digits"), "").js_string()
      Num((@string.parse_int(s) catch { _ => 0 }).to_double())
    },
    "return a.join('') + B;": ctx => {
      js_add(js_join(ctx.label("a"), ""), ctx.label("B"))
    },
    "return [a, A, b].join('');": ctx => {
      js_join(Arr([ctx.label("a"), ctx.label("A"), ctx.label("b")]), "")
    },
    "return [b, B, c].join('');": ctx => {
      js_join(Arr([ctx.label("b"), ctx.label("B"), ctx.label("c")]), "")
    },
    "return begin + ns.join('') + end;": ctx => {
      js_add(
        js_add(ctx.label("begin"), js_join(ctx.label("ns"), "")),
        ctx.label("end"),
      )
    },
  }
}

///|
/// Initializer blocks, keyed by their trimmed JavaScript text. Each returns
/// the per-parse bindings of the code blocks that share its state.
fn initializer_bindings() -> Map[String, InitFn[Unit]] {
  {
    "var n = 0;": _ => {
      let n = Ref(0.0)
      {
        "return n;": _ => Num(n.val),
        "n++;": _ => {
          n.val += 1.0
          Undefined
        },
      }
    },
    "var result = 42;": _ => { "return result;": _ => Num(42.0) },
    "var result = options;": init => {
      let result = V::Obj(init.options())
      { "return result;": _ => result }
    },
    "var v = 42": _ => {
      "return v === 42;": _ => Bool(true),
      "return v !== 42;": _ => Bool(false),
      "return v;": _ => Num(42.0),
    },
    "function f() { return 42; }": _ => {
      "return f() === 42;": _ => Bool(true),
      "return f() !== 42;": _ => Bool(false),
      "return f();": _ => Num(42.0),
    },
    "var result;": _ => {
      let result : Ref[V] = Ref(Undefined)
      {
        "return result;": _ => result.val,
        "result = options; return true;": ctx => {
          result.val = Obj(ctx.options())
          Bool(true)
        },
        "result = options; return false;": ctx => {
          result.val = Obj(ctx.options())
          Bool(false)
        },
        "result = location(); return true;": ctx => {
          result.val = ctx.location().to_value()
          Bool(true)
        },
        "result = location(); return false;": ctx => {
          result.val = ctx.location().to_value()
          Bool(false)
        },
        "result = location();": ctx => {
          result.val = ctx.location().to_value()
          Undefined
        },
      }
    },
  }
}

///|
fn value_of_json(j : Json) -> V {
  match j {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(n, ..) => Num(n)
    String(s) => Str(s)
    Array(xs) => Arr(xs.map(value_of_json))
    Object(m) =>
      match m.get("$") {
        Some(String("undefined")) => Undefined
        _ => {
          let r : Map[String, V] = Map([])
          for k, v in m {
            r[k] = value_of_json(v)
          }
          Obj(r)
        }
      }
  }
}

///|
fn error_json(e : Error) -> Json {
  match e {
    @runtime.SyntaxError(_) as e => e.to_json()
    @compiler.GrammarError(message~, location~) =>
      {
        "name": "GrammarError",
        "message": message,
        "location": location.to_json(),
      }
    @compiler.CompilerError(message) => { "name": "Error", "message": message }
    @runtime.ReferenceError(_) as e =>
      { "name": "ReferenceError", "message": e.to_string() }
    @runtime.InvalidStartRule(_) as e =>
      { "name": "Error", "message": e.to_string() }
    Thrown(_) => {}
    e => { "name": "unexpected", "message": "\{e}" }
  }
}

///|
test "generate and generated parsers match PEG.js" {
  let bindings = static_bindings()
  let initializers = initializer_bindings()
  let mut failures = 0
  let mut checked = 0
  fn report(what : String, expected : Json, actual : Json) {
    failures += 1
    if failures <= 8 {
      println(what)
      println("  expected: \{expected.stringify()}")
      println("  actual:   \{actual.stringify()}")
    }
  }

  for c in generate_cases {
    let options : Options[Unit] = Options::new(
      allowed_start_rules?=c.start,
      cache=c.cache,
      trace=c.trace,
      optimize=if c.size { Size } else { Speed },
      actions=bindings,
    )
    let expected = @json.parse(c.expected)
    let parser = try {
      let ast = @parser.parse(c.grammar)
      if ast.initializer is Some(init) {
        options.initializer = initializers.get(init.code.trim().to_owned())
      }
      generate(c.grammar, options~)
    } catch {
      e => {
        let actual = @fixture.normalize({ "error": error_json(e) })
        if actual != expected {
          report("generate differs: \{c.grammar}", expected, actual)
        }
        continue
      }
    }
    let ok : Json = { "ok": true }
    if expected != ok {
      report("generate unexpectedly succeeded: \{c.grammar}", expected, ok)
      continue
    }
    for p in c.parses {
      let (input, options_text, expected_text) = p
      checked += 1
      let expected = @json.parse(expected_text)
      let parse_options : Map[String, V] = match
        value_of_json(@json.parse(options_text)) {
        Obj(m) => m
        _ => {}
      }
      let tracer : Tracer[Unit]? = if c.trace {
        Some({ trace: _ => (), })
      } else {
        None
      }
      parse_options.remove("tracer")
      let actual : Json = try
        parser.parse(input, options=parse_options, tracer?)
      catch {
        e => { "error": error_json(e) }
      } noraise {
        v => { "ok": v.to_json_with(_ => Json::null()) }
      }
      let actual = @fixture.normalize(actual)
      if actual != expected {
        report(
          "parse differs: \{c.grammar} <- \{input} \{options_text}",
          expected,
          actual,
        )
      }
    }
  }
  println("checked \{generate_cases.length()} grammars, \{checked} parses")
  assert_eq(failures, 0)
}
