///|
/// Generates the MoonBit parser source for `grammar` as configured by
/// `options`.
pub fn generate(options : CliOptions, grammar : String) -> String raise {
  let features : Map[String, Bool] = Map([])
  for k, v in options.features {
    features[k] = v
  }
  let opts : @peg.Options[Unit] = @peg.Options::new(
    allowed_start_rules?=options.allowed_start_rules,
    cache=options.cache,
    optimize=if options.optimize == "size" { Size } else { Speed },
    trace=options.trace,
    features~,
    header=options.header,
    value_type=options.value_type,
    name_prefix=options.name_prefix,
  )
  if options.reserved_words is Some(words) {
    opts.parser.reserved_words = Some(words)
  }
  if options.input_file is Some(f) && f != "-" {
    opts.parser.filename = Some(f)
  }
  @peg.generate_source(grammar, options=opts)
}

///|
/// Human-readable message for errors raised while generating.
pub fn describe_error(e : Error) -> String {
  match e {
    @runtime.SyntaxError(message~, location~, ..) =>
      "\{location.start.line}:\{location.start.column}: \{message}"
    @compiler.GrammarError(message~, location~) =>
      "\{location.start.line}:\{location.start.column}: \{message}"
    @compiler.CompilerError(message) => message
    CliError(message) => message
    e => "\{e}"
  }
}
