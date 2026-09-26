///|
/// A string-keyed dictionary with the semantics of a plain JavaScript object
/// used as a map, which is how PEG.js stores label environments and rule
/// tables:
///
/// * assigning `__proto__` is a no-op for non-object values, so that key is
///   never stored (and lookups of it fail);
/// * `Object.keys` order lists array-index keys ("0", "1", ...) first in
///   ascending numeric order, then other keys in insertion order.
priv struct JsDict[V] {
  map : Map[String, V]
}

///|
fn[V] JsDict::new() -> JsDict[V] {
  { map: {}, }
}

///|
fn[V] JsDict::clone(self : JsDict[V]) -> JsDict[V] {
  { map: self.map.copy(), }
}

///|
fn[V] JsDict::set(self : JsDict[V], key : String, value : V) -> Unit {
  if key != "__proto__" {
    self.map[key] = value
  }
}

///|
fn[V] JsDict::get(self : JsDict[V], key : String) -> V? {
  self.map.get(key)
}

///|
/// Parses `key` as a JavaScript array index (canonical decimal < 2^32 - 1).
fn array_index(key : String) -> Int64? {
  if key == "" ||
    key.length() > 10 ||
    (key.length() > 1 && key.code_unit_at(0) == '0') {
    return None
  }
  let mut n = 0L
  for i in 0..<key.length() {
    let c = key.code_unit_at(i).to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      return None
    }
    n = n * 10L + (c - '0'.to_int()).to_int64()
  }
  if n < 4294967295L {
    Some(n)
  } else {
    None
  }
}

///|
/// Keys in `Object.keys` order.
fn[V] JsDict::keys(self : JsDict[V]) -> Array[String] {
  let indices : Array[(Int64, String)] = []
  let others : Array[String] = []
  for k, _ in self.map {
    match array_index(k) {
      Some(n) => indices.push((n, k))
      None => others.push(k)
    }
  }
  indices.sort_by_key(p => p.0)
  indices.map(p => p.1) + others
}
