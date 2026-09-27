# peg.mbt

[![CI](https://github.com/bobzhang/peg.mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/bobzhang/peg.mbt/actions/workflows/ci.yml)

A MoonBit port of [PEG.js](https://github.com/pegjs/pegjs) (dev branch, v0.11.0,
commit `b7b87ea`): a parser generator based on parsing expression grammars.

It keeps the PEG.js grammar language, compiler passes, bytecode, error reporting
and generated-parser behaviour, and offers two ways to use a grammar:

- **At runtime**: `@peg.generate(grammar)` returns a parser that interprets the
  compiled bytecode. Code blocks are implemented by MoonBit closures.
- **As generated source**: `pegmbt` (or `@peg.generate_source`) emits a
  standalone MoonBit parser whose `{ ... }` code blocks are MoonBit code.

## Fidelity

The port is differentially tested against the reference implementation, which
is run with Node on the harvested inputs of its own test suite (see
[Development](#development)):

| What | Cases | Result |
| --- | --- | --- |
| Grammar parser: ASTs (locations, comments) and syntax errors | 595 | identical |
| Compiler passes run directly (checks, transforms, bytecode) | 214 | identical |
| `generate()` + parse, over cache/trace/optimize variants | 1108 grammars, 1656 parses | identical |
| Bytecode of `examples/{arithmetics,json,css,javascript}.pegjs` and of PEG.js' own grammar | 5 | identical |
| Generated MoonBit parsers (speed/size × cache × trace) | 753 parsers, 1248 parses | identical |
| Parser generated from PEG.js' grammar rewritten with MoonBit code blocks | 595 | identical |

Parsing semantics are those of the JavaScript original: input is indexed by
UTF-16 code units, case-insensitive literals use `String.prototype.toLowerCase`
(Final_Sigma included), and case-insensitive classes follow non-unicode `/i`
regexp canonicalization. The case tables are captured from V8 (Node 25,
Unicode 17) by `tools/gen-unicode.js`. PEG.js quirks are kept as well: for
example, class descriptions join their parts with commas (`Expected [a-c,x]`),
an empty expectation list reads `Expected , or undefined`, only `\n` starts a
new line, `[^]` never matches, and cached rules replay their expectations.

## Runtime parsers

Build a parser from a grammar string. Code blocks are bound by their text,
so a grammar written for the runtime can simply name its actions:

```mbt check
///|
test "runtime parser with actions" {
  let grammar =
    #|start = head:number tail:("+" @number)* { sum }
    #|number = [0-9]+ { toNumber }
  let parser : @peg.Parser[Unit] = @peg.generate(
    grammar,
    options=@peg.Options::new(actions={
      "toNumber": ctx => {
        let mut n = 0.0
        for c in ctx.text() {
          n = n * 10.0 + (c.to_int() - '0'.to_int()).to_double()
        }
        Num(n)
      },
      "sum": ctx => {
        let mut total = ctx.label("head")
        for x in ctx.label("tail").as_arr().unwrap() {
          guard (total, x) is (Num(a), Num(b)) else { fail("not numbers") }
          total = Num(a + b)
        }
        total
      },
    }),
  )
  debug_inspect(parser.parse("1+20+300"), content="Num(321)")
}
```

Without code blocks, results are the dynamic values PEG.js produces: strings
for literals, classes and `.`, arrays for sequences and repetitions, `Null` for
a failed `?`, `Undefined` for predicates:

```mbt check
///|
test "default values and errors" {
  let parser : @peg.Parser[Unit] = @peg.generate("start = 'a' [0-9]? $('b'+)")
  debug_inspect(
    parser.parse("abbb"),
    content=(
      #|Arr([Str("a"), Null, Str("bbb")])
    ),
  )
  let message = try parser.parse("ac") catch {
    @runtime.SyntaxError(message~, ..) => message
    _ => "other error"
  } noraise {
    _ => "parsed"
  }
  inspect(
    message,
    content=(
      #|Expected "b" or [0-9] but "c" found.
    ),
  )
}
```

- `ActionContext` (`ctx`) gives the labels in scope (`ctx.label("x")`) and the
  PEG.js helpers: `text()`, `offset()`, `range()`, `location()`,
  `expected(description, location?)`, `error(message, location?)`, `options()`.
- A binding is looked up by `"#<index>"`, then by exact code, then by trimmed
  code. Identical code blocks with different labels share a text key, so read
  labels by name.
- Predicates return a `Value`, judged by JavaScript truthiness.
- A grammar initializer needs `Options::initializer`: it runs once per parse
  and returns bindings, so actions can share per-parse state.
- Options: `allowed_start_rules`, `cache`, `trace`, `optimize`, `features`,
  `parser` (reserved words, comments) and plugins, as in PEG.js. `parse`
  accepts `start_rule`, `filename`, `tracer` and `options`.

## Generated parsers

Write code blocks in MoonBit:

```mbt nocheck
{
  // The initializer runs once per parse; its definitions are visible to all
  // code blocks.
  fn num(v : PegValue) -> Double {
    match v {
      Num(n) => n
      _ => 0.0
    }
  }
}

Sum
  = head:Integer tail:(_ "+" _ @Integer)* {
      let mut total = num(head)
      for x in tail.as_arr().unwrap() {
        total = total + num(x)
      }
      Num(total)
    }

Integer "integer"
  = [0-9]+ &{ ctx.text().length() < 10 } { Num(@string.parse_double(ctx.text())) }

_ = " "*
```

and generate the parser:

```bash
moon run --target native cmd/pegmbt -- sum.pegjs        # writes sum.mbt
```

The generated file defines `pub fn parse(input, start_rule?, filename?,
tracer?, options?) -> PegValue raise` and belongs to a package importing
`"bobzhang/peg/runtime"` and `"bobzhang/peg/vm"` (plus `"bobzhang/peg/bytecode"` with
`-O size`). Types and helper functions can live in sibling files of that
package. See `examples/arithmetics` and `examples/json`.

Conventions for code blocks:

- Actions are function bodies returning `PegValue` (`@runtime.Value[T]`), with
  the labels in scope as `PegValue` parameters, so labels must be MoonBit
  identifiers (lowercase, not keywords).
- Predicates (`&{ }`, `!{ }`) return a `Bool` or a `PegValue` (truthiness).
- `ctx : @runtime.ActionContext[T]` provides `text()`, `location()`, `error()`,
  the other helpers, and `ctx.label(name)`.
- The initializer is pasted into a per-parse function. It must fall through
  (no `return`), and generated names start with `peg_` / `Peg`.
- As in PEG.js, code blocks end at the first unbalanced `}`, even when that
  brace is inside a string or comment.

`pegmbt` options mirror PEG.js' `pegjs` command: `-a/--allowed-start-rules`,
`--cache`, `--trace`, `-O/--optimize speed|size`, `-o/--output`,
`--extra-options(-file)` (JSON), plus `--value-type <T>` (payload type of
`Value[T]`, default `Unit`) and `--name-prefix <p>` (prefix generated names so
several parsers can share a package).

## Differences from PEG.js

- The JavaScript output formats (`format`, `dependencies`, `exportVar`) are
  dropped. `pegmbt` cannot load JavaScript plugins (`-p`); library plugins are
  MoonBit functions receiving the `Session` (grammar parser, passes, opcodes,
  reporters, backend) and the options.
- Code blocks are MoonBit: bound closures at runtime, source text in generated
  parsers. When source is generated, labels must be valid MoonBit identifiers,
  and MoonBit keywords are the default reserved words.
- An action referring to an out-of-scope label raises `ReferenceError` at
  runtime; in generated source it is a compile error.
- A class whose line continuations produce an out-of-order regexp range
  (e.g. `[z\<newline>-a]`) makes PEG.js' `generate` fail on the invalid
  regexp; here that range matches nothing.

## Packages

| Package | Contents |
| --- | --- |
| `bobzhang/peg` | `generate`, `generate_source`, `new_session`, re-exports |
| `bobzhang/peg/runtime` | `Value`, locations, expectations, errors, parse state, JS string semantics |
| `bobzhang/peg/bytecode` | opcodes and compiled `Program`s |
| `bobzhang/peg/ast` | grammar AST (JSON-compatible with PEG.js') |
| `bobzhang/peg/parser` | the grammar parser (frozen bytecode of `src/parser.pegjs`) |
| `bobzhang/peg/compiler` | session, options and all compiler passes |
| `bobzhang/peg/vm` | the bytecode interpreter |
| `bobzhang/peg/codegen` | MoonBit source generation |
| `bobzhang/peg/cli`, `cmd/pegmbt` | the command-line tool (native) |

## Development

`.repos/pegjs` holds the reference implementation, and `tools/` holds the Node
harness around it. Install the harness with `npm install` in `tools/`:

- `tools/harvest.js`: a mocha hook that records every grammar parse, pass
  invocation, `generate` and parse of the upstream test suite into
  `tools/corpus.jsonl`.
- `tools/gen-fixtures.js`: turns the corpus into the MoonBit differential tests.
- `tools/gen-codegen-corpus.js`: generates `internal/codegen_corpus` with
  `pegmbt`, using the MoonBit versions of the upstream test code blocks from
  `tools/mbt-code-blocks.js`.
- `tools/gen-program.js`, `tools/gen-self-host.js`, `tools/gen-unicode.js`:
  produce the frozen meta-grammar program, the self-hosted grammar and the case
  tables.

- `tools/regenerate.sh`: rebuilds every generated file from the pinned
  reference; CI checks that the result matches the repository.

```bash
moon test --target all
```
