///|
fn read_input(file : String) -> String raise {
  @fs.read_file_to_string(if file == "-" { "/dev/stdin" } else { file })
}

///|
fn main {
  let args = @env.args()
  let command = @cli.parse_args(args[1:].to_owned(), read_file=read_input) catch {
    e => {
      println(@cli.describe_error(e))
      @sys.exit(1)
      return
    }
  }
  match command {
    Help => println(@cli.usage)
    Version => println("peg.mbt v\{@codegen.version} (PEG.js v\{@peg.version})")
    Generate(options) => {
      let input = options.input_file.unwrap()
      let grammar = read_input(input) catch {
        _ => {
          println("Can't read from file \"\{input}\".")
          @sys.exit(1)
          return
        }
      }
      let source = @cli.generate(options, grammar) catch {
        e => {
          println(@cli.describe_error(e))
          @sys.exit(1)
          return
        }
      }
      let output = options.output_file.unwrap()
      if output == "-" {
        println(source.trim_end(chars="\n").to_owned())
      } else {
        @fs.write_string_to_file(output, source) catch {
          _ => {
            println("Can't write to file \"\{output}\".")
            @sys.exit(1)
          }
        }
      }
    }
  }
}
