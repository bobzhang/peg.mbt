///|
/// PEG.js version this port follows.
pub let version : String = "0.11.0"

///|
pub using @runtime {
  type Value,
  type ActionContext,
  type ActionFn,
  type InitFn,
  type Location,
  type Pos,
  type Expectation,
  type SyntaxError,
  type Tracer,
  type TraceEvent,
}

///|
pub using @vm {type Parser}

///|
pub using @compiler {
  type Session,
  type Options,
  type Optimize,
  type Output,
  type GrammarError,
  type CompilerError,
}

///|
/// A plugin: may inspect and modify the session (parser, passes, opcodes,
/// backend, reporters) and the options before compilation (`plugin.use`).
pub type Plugin[T] = (Session[T], Options[T]) -> Unit raise

///|
/// A session with the standard grammar parser and passes, including the
/// `generateMoonBit` source generation pass.
pub fn[T] new_session() -> Session[T] {
  let session = Session::new(parser=(input, options) => {
    @parser.parse(
      input,
      reserved_words?=options.reserved_words,
      extract_comments=options.extract_comments,
      filename?=options.filename,
    )
  })
  session.passes.generate.push({
    name: "generateMoonBit",
    run: @codegen.generate_moonbit,
  })
  session
}

///|
/// Generates a parser from a PEG.js grammar (`peg.generate`).
///
/// Code blocks in the grammar are implemented in MoonBit through `actions`
/// (keyed by the block's code text, see `@vm.lookup_binding`) and
/// `initializer`. Raises `SyntaxError` for invalid grammar syntax,
/// `GrammarError` / `CompilerError` for semantic errors and
/// `@vm.UnboundCode` for code blocks without an implementation.
pub fn[T] generate(
  grammar : String,
  options? : Options[T] = Options::new(),
  plugins? : Array[Plugin[T]] = [],
) -> Parser[T] raise {
  let session : Session[T] = new_session()
  for plugin in plugins {
    plugin(session, options)
  }
  let ast = session.parse(grammar, options.parser)
  match @compiler.compile(ast, session, options) {
    Parser(parser) => parser
    Source(_) =>
      raise @compiler.CompilerError(
        "generate() returns a parser; use output=Parser (source generation is not available through generate)",
      )
  }
}

///|
/// Generates the MoonBit source of a parser for `grammar`, whose code blocks
/// contain MoonBit code (see the `codegen` package for the conventions).
///
/// Labels may not be MoonBit keywords unless `options.parser.reserved_words`
/// says otherwise. Raises like `generate`.
pub fn[T] generate_source(
  grammar : String,
  options? : Options[T] = Options::new(),
  plugins? : Array[Plugin[T]] = [],
) -> String raise {
  options.output = Source
  if options.parser.reserved_words is None {
    options.parser.reserved_words = Some(@codegen.reserved_words())
  }
  let session : Session[T] = new_session()
  for plugin in plugins {
    plugin(session, options)
  }
  let ast = session.parse(grammar, options.parser)
  match @compiler.compile(ast, session, options) {
    Source(code) => code
    Parser(_) =>
      raise @compiler.CompilerError("generate_source() requires output=Source")
  }
}
