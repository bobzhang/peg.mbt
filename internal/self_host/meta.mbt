// Support code for the self-hosted grammar parser generated from
// parser.pegjs (PEG.js' own grammar with MoonBit code blocks).

///|
/// AST values built by the grammar's code blocks.
pub(all) enum Meta {
  N(@ast.Node)
  R(@ast.Rule)
  I(@ast.Initializer)
  G(@ast.Grammar)
}

///|
fn str(v : PegValue) -> String {
  match v {
    Str(s) => s
    _ => abort("expected a string")
  }
}

///|
fn arr(v : PegValue) -> Array[PegValue] {
  match v {
    Arr(xs) => xs
    _ => abort("expected an array")
  }
}

///|
fn node(v : PegValue) -> @ast.Node {
  match v {
    Custom(N(n)) => n
    _ => abort("expected an AST node")
  }
}

///|
fn joined(v : PegValue) -> String {
  let sb = StringBuilder()
  for x in arr(v) {
    sb.write_string(str(x))
  }
  sb.to_string()
}

///|
fn hex(digits : String) -> Int {
  let mut n = 0
  for c in digits {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      c.to_int() - 'A'.to_int() + 10
    }
    n = n * 16 + d
  }
  n
}

///|
fn js_reserved_words() -> Array[String] {
  [..@parser.js_reserved_words]
}

///|
/// Parses PEG.js grammar source with the self-hosted parser.
pub fn parse_grammar(
  input : String,
  extract_comments? : Bool = false,
) -> @ast.Grammar raise {
  match parse(input, options={ "extractComments": Bool(extract_comments) }) {
    Custom(G(g)) => g
    _ => abort("expected a grammar")
  }
}
