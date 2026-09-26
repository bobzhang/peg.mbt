// Command-line handling of `pegmbt`, ported from PEG.js' bin/options.js.
// Pure (no I/O): `run` receives a file reader so it works on every backend.

///|
/// Usage text (`bin/usage.js`, adapted to MoonBit output).
pub let usage : String =
  #|Usage: pegmbt [options] [<input_file>] [--]
  #|
  #|Options:
  #|
  #|-a, --allowed-start-rules <rules>  Comma-separated list of rules the generated
  #|                                   parser will be allowed to start parsing from
  #|                                   (default: first rule in the grammar)
  #|                                   (note: repeatable option)
  #|
  #|    --cache                        Make generated parser cache results
  #|
  #|-c, --config <file>                Aliases for "--extra-options-file"
  #|
  #|    --extra-options <options>      A string with additional options (in JSON
  #|                                   format) to pass to generate_source
  #|                                   (note: repeatable option)
  #|
  #|    --extra-options-file <file>    File with additional options (in JSON
  #|                                   format) to pass to generate_source
  #|                                   (note: repeatable option)
  #|
  #|-h, --help                         Print help and exit
  #|
  #|    --no-cache                     Generated parser doesn't cache results
  #|                                   (default behavior)
  #|
  #|    --no-trace                     Disable tracing in generated parser
  #|                                   (default behavior)
  #|
  #|-O, --optimize <goal>              Select optimization for speed or size
  #|                                   (default: speed)
  #|
  #|-o, --output <file>                Output file (default: input file with the
  #|                                   extension replaced by ".mbt"; stdout for
  #|                                   stdin input)
  #|
  #|    --trace                        Enable tracing in generated parser
  #|
  #|    --name-prefix <prefix>         Prefix for the generated top-level names
  #|                                   (e.g. "calc_" gives calc_parse, Calc_PegValue)
  #|
  #|    --value-type <type>            MoonBit payload type T of Value[T] in the
  #|                                   generated parser (default: Unit)
  #|
  #|-v, --version                      Print version information and exit
  #|
  #|JavaScript-specific PEG.js options (-d/--dependency, -e/--export-var,
  #|-f/--format, -p/--plugin) are not supported.
  #|

///|
/// Parsed command line.
pub(all) struct CliOptions {
  mut input_file : String?
  mut output_file : String?
  mut allowed_start_rules : Array[String]?
  mut cache : Bool
  mut optimize : String
  mut trace : Bool
  mut value_type : String
  mut name_prefix : String
  mut header : Array[String]
  mut features : Map[String, Bool]
  mut reserved_words : Array[String]?
  mut rest : Array[String]
} derive(Debug)

///|
/// What the command line asks for.
pub(all) enum Command {
  Help
  Version
  Generate(CliOptions)
} derive(Debug)

///|
/// Invalid command line; the message is printed and the process exits 1.
pub(all) suberror CliError {
  CliError(String)
} derive(Debug)

///|
fn update_list(list : Array[String], s : String) -> Unit {
  for entry in s.split(",") {
    let entry = entry.trim().to_owned()
    if !list.contains(entry) {
      list.push(entry)
    }
  }
}

///|
fn string_list(j : Json, name : String) -> Array[String] raise CliError {
  guard j is Array(xs) else {
    raise CliError("The option `\{name}` must be an array of strings.")
  }
  xs.map(x => {
    match x {
      String(s) => s
      _ => raise CliError("The option `\{name}` must be an array of strings.")
    }
  })
}

///|
/// Merges a JSON object of extra options (`addExtraOptions`). As in PEG.js,
/// they override options given earlier on the command line.
fn add_extra_options(
  options : CliOptions,
  text : String,
) -> Unit raise CliError {
  let config = @json.parse(text) catch {
    e => raise CliError("Error parsing JSON: \{e}")
  }
  guard config is Object(fields) else {
    raise CliError("The JSON with extra options has to represent an object.")
  }
  for key, value in fields {
    match key {
      "input" =>
        match value {
          String(input) => {
            if options.input_file is Some(_) {
              raise CliError(
                "The input file is already set, cannot use: \"\{input}\".",
              )
            }
            options.input_file = Some(input)
          }
          Null => ()
          _ => raise CliError("The option `input` must be a string.")
        }
      "output" =>
        match value {
          String(output) => options.output_file = Some(output)
          Null => ()
          _ => raise CliError("The option `output` must be a string.")
        }
      "allowedStartRules" =>
        options.allowed_start_rules = Some(
          string_list(value, "allowedStartRules"),
        )
      "cache" => options.cache = value is True
      "trace" => options.trace = value is True
      "optimize" =>
        match value {
          String("speed" | "size" as goal) => options.optimize = goal
          _ =>
            raise CliError(
              "Optimization goal must be either \"size\" or \"speed\".",
            )
        }
      "namePrefix" =>
        match value {
          String(t) => options.name_prefix = t
          _ => raise CliError("The option `namePrefix` must be a string.")
        }
      "valueType" =>
        match value {
          String(t) => options.value_type = t
          _ => raise CliError("The option `valueType` must be a string.")
        }
      "header" =>
        match value {
          String(h) => options.header = [h]
          Array(_) => options.header = string_list(value, "header")
          _ => raise CliError("The option `header` must be a string or array.")
        }
      "features" =>
        match value {
          Object(fs) => {
            // Like PEG.js' shallow option merge, a new object replaces the
            // previous one.
            let features : Map[String, Bool] = Map([])
            for name, enabled in fs {
              features[name] = enabled is True
            }
            options.features = features
          }
          _ => raise CliError("The option `features` must be an object.")
        }
      "parser" =>
        match value {
          Object(p) =>
            if p.get("reservedWords") is Some(words) {
              options.reserved_words = Some(string_list(words, "reservedWords"))
            }
          _ => raise CliError("The option `parser` must be an object.")
        }
      "format" | "dependencies" | "exportVar" | "plugins" | "context" =>
        raise CliError(
          "The option `\{key}` is JavaScript-specific and not supported.",
        )
      _ => ()
    }
  }
}

///|
/// Parses command-line arguments (without the program name).
/// `read_file` loads `--extra-options-file` configs.
pub fn parse_args(
  args : Array[String],
  read_file~ : (String) -> String raise,
) -> Command raise CliError {
  let options : CliOptions = {
    input_file: None,
    output_file: None,
    allowed_start_rules: None,
    cache: false,
    optimize: "speed",
    trace: false,
    value_type: "Unit",
    name_prefix: "",
    header: [],
    features: {},
    reserved_words: None,
    rest: [],
  }
  let queue = args.copy()
  queue.rev_in_place()
  fn next_arg(option : String) -> String raise CliError {
    match queue.pop() {
      Some(arg) => arg
      None => raise CliError("Missing parameter of the \{option} option.")
    }
  }

  while queue.pop() is Some(arg) {
    let mut argument = arg
    if argument.has_prefix("-") {
      match argument.find("=") {
        Some(i) if i > 1 => {
          queue.push(
            argument.unsafe_substring(start=i + 1, end=argument.length()),
          )
          argument = argument.unsafe_substring(start=0, end=i)
        }
        _ => ()
      }
    }
    match argument {
      "--" => {
        queue.rev_in_place()
        options.rest = queue.copy()
        queue.clear()
      }
      "-a" | "--allowed-start-rules" => {
        let rules = match options.allowed_start_rules {
          Some(rules) => rules
          None => {
            let rules = []
            options.allowed_start_rules = Some(rules)
            rules
          }
        }
        update_list(rules, next_arg("--allowed-start-rules"))
      }
      "--cache" => options.cache = true
      "--no-cache" => options.cache = false
      "--extra-options" =>
        add_extra_options(options, next_arg("--extra-options"))
      "-c" | "--config" | "--extra-options-file" => {
        let file = next_arg("-c/--config/--extra-options-file")
        let text = read_file(file) catch {
          _ => raise CliError("Can't read from file \"\{file}\".")
        }
        add_extra_options(options, text)
      }
      "-h" | "--help" => return Help
      "-O" | "--optimize" => {
        let goal = next_arg("-O/--optimize")
        guard goal is ("size" | "speed") else {
          raise CliError(
            "Optimization goal must be either \"size\" or \"speed\".",
          )
        }
        options.optimize = goal
      }
      "-o" | "--output" => options.output_file = Some(next_arg("-o/--output"))
      "--trace" => options.trace = true
      "--no-trace" => options.trace = false
      "--value-type" => options.value_type = next_arg("--value-type")
      "--name-prefix" => options.name_prefix = next_arg("--name-prefix")
      "-v" | "--version" => return Version
      "-d"
      | "--dependency"
      | "-e"
      | "--export-var"
      | "-f"
      | "--format"
      | "-p"
      | "--plugin" =>
        raise CliError(
          "The \{argument} option is JavaScript-specific and not supported.",
        )
      _ =>
        if options.input_file is Some(_) {
          raise CliError("Unknown option: \"\{argument}\".")
        } else {
          options.input_file = Some(argument)
        }
    }
  }
  let input = match options.input_file {
    Some(input) => input
    None => "-"
  }
  options.input_file = Some(input)
  if options.output_file is None {
    options.output_file = Some(
      if input == "-" {
        "-"
      } else {
        replace_extension(input, ".mbt")
      },
    )
  }
  Generate(options)
}

///|
/// `input.substr(0, input.length - path.extname(input).length) + ext`.
pub fn replace_extension(file : String, ext : String) -> String {
  let base_start = match file.rev_find("/") {
    Some(i) => i + 1
    None => 0
  }
  let base = file.unsafe_substring(start=base_start, end=file.length())
  // `path.extname`: from the last "." of the basename, unless it is the
  // first character.
  match base.rev_find(".") {
    Some(i) if i > 0 => file.unsafe_substring(start=0, end=base_start + i) + ext
    _ => file + ext
  }
}
