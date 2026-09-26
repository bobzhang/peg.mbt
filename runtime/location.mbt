///|
/// A position in the input: a UTF-16 code-unit offset plus 1-based line and
/// column (lines are only broken by `\n`, as in PEG.js).
pub(all) struct Pos {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// A span of the input, optionally tagged with the source file name.
pub(all) struct Location {
  filename : String?
  start : Pos
  end : Pos
} derive(Eq, Debug)

///|
pub impl ToJson for Pos with fn to_json(self) {
  { "offset": self.offset, "line": self.line, "column": self.column }
}

///|
pub impl ToJson for Location with fn to_json(self) {
  let obj : Map[String, Json] = Map([])
  if self.filename is Some(f) {
    obj["filename"] = f.to_json()
  }
  obj["start"] = self.start.to_json()
  obj["end"] = self.end.to_json()
  Json::object(obj)
}

///|
/// Incremental offset -> line/column computation with the same caching
/// strategy as the generated `peg$computePosDetails`.
pub struct PosCache {
  input : String
  details : Map[Int, (Int, Int)]
  filename : String?
}

///|
pub fn PosCache::new(input : String, filename? : String) -> PosCache {
  { input, details: { 0: (1, 1) }, filename, }
}

///|
pub fn PosCache::pos(self : PosCache, offset : Int) -> Pos {
  match self.details.get(offset) {
    Some((line, column)) => { offset, line, column, }
    None => {
      let mut p = offset - 1
      while !self.details.contains(p) {
        p -= 1
      }
      let (line0, column0) = self.details[p]
      let mut line = line0
      let mut column = column0
      while p < offset {
        if p < self.input.length() && self.input.code_unit_at(p) == '\n' {
          line += 1
          column = 1
        } else {
          column += 1
        }
        p += 1
      }
      self.details[offset] = (line, column)
      { offset, line, column, }
    }
  }
}

///|
pub fn PosCache::location(self : PosCache, start : Int, end : Int) -> Location {
  { filename: self.filename, start: self.pos(start), end: self.pos(end), }
}

///|
/// The location as a `Value` object, shaped like PEG.js' location objects.
pub fn[T] Location::to_value(self : Location) -> Value[T] {
  fn pos(p : Pos) -> Value[T] {
    Obj({
      "offset": Num(p.offset.to_double()),
      "line": Num(p.line.to_double()),
      "column": Num(p.column.to_double()),
    })
  }

  let obj : Map[String, Value[T]] = Map([])
  if self.filename is Some(f) {
    obj["filename"] = Str(f)
  }
  obj["start"] = pos(self.start)
  obj["end"] = pos(self.end)
  Obj(obj)
}
