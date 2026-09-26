// JavaScript-semantics helpers used by the MoonBit translations of the
// upstream test grammars' code blocks (copied into each codegen corpus
// package by tools/gen-codegen-corpus.js).

///|
#warnings("-unused_value")
fn js_number(v : @runtime.Value[Unit]) -> Double {
  match v {
    Num(n) => n
    Bool(b) => if b { 1.0 } else { 0.0 }
    Null => 0.0
    Str(_) | Arr(_) => {
      let s = v.js_string().trim()
      if s.is_empty() {
        return 0.0
      }
      let mut n = 0.0
      for c in s {
        if c < '0' || c > '9' {
          return 0.0 / 0.0
        }
        n = n * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      }
      n
    }
    _ => 0.0 / 0.0
  }
}

///|
#warnings("-unused_value")
fn js_add(
  a : @runtime.Value[Unit],
  b : @runtime.Value[Unit],
) -> @runtime.Value[Unit] {
  match (a, b) {
    (Str(_) | Arr(_) | Obj(_) | Custom(_), _)
    | (_, Str(_) | Arr(_) | Obj(_) | Custom(_)) =>
      Str(a.js_string() + b.js_string())
    _ => Num(js_number(a) + js_number(b))
  }
}

///|
#warnings("-unused_value")
fn js_join(v : @runtime.Value[Unit], sep : String) -> @runtime.Value[Unit] {
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
/// `tail.reduce((result, element) => element[0] === plus ? result <plus>
/// element[1] : element[0] === minus ? result <minus> element[1] :
/// undefined, head)`.
#warnings("-unused_value")
fn js_reduce(
  head : @runtime.Value[Unit],
  tail : @runtime.Value[Unit],
  plus : String,
  minus : String,
) -> @runtime.Value[Unit] {
  let mut result = head
  for element in tail.as_arr().unwrap() {
    let el = element.as_arr().unwrap()
    let x = js_number(result)
    let y = js_number(el[1])
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
