///|
/// Reads a regular file (config files and grammar files).
fn read_file(file : String) -> String raise {
  @fs.read_file_to_string(file)
}

///|
async fn fail_with(message : String) -> Unit {
  @stdio.stderr.write(message + "\n")
  @sys.exit(1)
}

///|
async fn main {
  let args = @env.args()
  let command = @cli.parse_args(args[1:].to_owned(), read_file~) catch {
    e => {
      fail_with(@cli.describe_error(e))
      return
    }
  }
  match command {
    Help => @stdio.stdout.write(@cli.usage)
    Version =>
      @stdio.stdout.write(
        "peg.mbt v\{@codegen.version} (PEG.js v\{@peg.version})\n",
      )
    Generate(options) => {
      let input = options.input_file.unwrap()
      // Standard input is a stream (possibly a pipe): read it to the end.
      let grammar = try {
        if input == "-" {
          @stdio.stdin.read_all().text()
        } else {
          read_file(input)
        }
      } catch {
        _ => {
          fail_with("Can't read from file \"\{input}\".")
          return
        }
      }
      let source = @cli.generate(options, grammar) catch {
        e => {
          fail_with(@cli.describe_error(e))
          return
        }
      }
      let output = options.output_file.unwrap()
      if output == "-" {
        @stdio.stdout.write(source)
      } else {
        @fs.write_string_to_file(output, source) catch {
          _ => fail_with("Can't write to file \"\{output}\".")
        }
      }
    }
  }
}
