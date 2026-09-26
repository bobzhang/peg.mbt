///|
fn items(v : PegValue) -> Array[PegValue] {
  match v {
    Arr(xs) => xs
    _ => abort("expected an array")
  }
}

///|
fn text_of(v : PegValue) -> String {
  match v {
    Str(s) => s
    _ => abort("expected a string")
  }
}
