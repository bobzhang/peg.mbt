///|
/// A dynamically typed value produced by a PEG.js-style parser.
///
/// Mirrors the JavaScript values PEG.js parsers produce: literals, classes and
/// `.` yield `Str`, sequences and repetitions yield `Arr`, `?` yields `Null`
/// on failure and predicates yield `Undefined`. `Custom` carries application
/// payloads produced by actions.
pub(all) enum Value[T] {
  Undefined
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  Arr(Array[Value[T]])
  Obj(Map[String, Value[T]])
  Custom(T)
} derive(Eq, Debug)

///|
/// JavaScript truthiness, used for semantic predicates.
pub fn[T] Value::truthy(self : Value[T]) -> Bool {
  match self {
    Undefined | Null => false
    Bool(b) => b
    Num(n) => !(n == 0.0 || n.is_nan())
    Str(s) => s != ""
    Arr(_) | Obj(_) | Custom(_) => true
  }
}

///|
/// Returns the string payload, if any.
pub fn[T] Value::as_str(self : Value[T]) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
/// Returns the array payload, if any.
pub fn[T] Value::as_arr(self : Value[T]) -> Array[Value[T]]? {
  match self {
    Arr(a) => Some(a)
    _ => None
  }
}

///|
/// Converts to JSON. `Undefined` becomes `{"$": "undefined"}` and custom
/// payloads are rendered with `custom`, matching the fixture encoding of
/// tools/harvest.js.
pub fn[T] Value::to_json_with(self : Value[T], custom : (T) -> Json) -> Json {
  match self {
    Undefined => { "$": "undefined" }
    Null => Json::null()
    Bool(b) => b.to_json()
    Num(n) =>
      if n.is_nan() {
        { "$": "number", "value": "NaN" }
      } else if n.is_inf() {
        {
          "$": "number",
          "value": if n > 0.0 {
            "Infinity"
          } else {
            "-Infinity"
          },
        }
      } else {
        Json::number(n)
      }
    Str(s) => s.to_json()
    Arr(xs) => Json::array(xs.map(x => x.to_json_with(custom)))
    Obj(m) => {
      let obj : Map[String, Json] = Map([])
      for k, v in m {
        obj[k] = v.to_json_with(custom)
      }
      Json::object(obj)
    }
    Custom(t) => custom(t)
  }
}

///|
pub impl[T : ToJson] ToJson for Value[T] with fn to_json(self) {
  self.to_json_with(t => t.to_json())
}

///|
/// JavaScript `String(value)`. Objects and custom payloads render as
/// `[object Object]`.
pub fn[T] Value::js_string(self : Value[T]) -> String {
  match self {
    Undefined => "undefined"
    Null => "null"
    Bool(b) => b.to_string()
    Num(n) => n.to_string()
    Str(s) => s
    Arr(xs) =>
      xs
      .map(x => {
        match x {
          Undefined | Null => ""
          _ => x.js_string()
        }
      })
      .join(",")
    Obj(_) | Custom(_) => "[object Object]"
  }
}
