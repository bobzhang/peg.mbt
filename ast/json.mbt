// JSON rendering of the AST, identical in shape to the PEG.js AST objects
// (used for differential testing against the reference implementation).

///|
pub impl ToJson for Node with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": Json(self.type_name()),
    "location": self.location.to_json(),
  }
  match self.kind {
    Named(e, name~) => {
      obj["name"] = Json(name)
      obj["expression"] = e.to_json()
    }
    Choice(alternatives) => obj["alternatives"] = Json(alternatives)
    Action(e, code~) => {
      obj["expression"] = e.to_json()
      obj["code"] = Json(code)
    }
    Sequence(elements) => obj["elements"] = Json(elements)
    Labeled(e, label~, pick~) => {
      if pick {
        obj["pick"] = Json(true)
      }
      obj["label"] = match label {
        Some(l) => Json(l)
        None => Json::null()
      }
      obj["expression"] = e.to_json()
    }
    Text(e)
    | SimpleAnd(e)
    | SimpleNot(e)
    | Optional(e)
    | ZeroOrMore(e)
    | OneOrMore(e)
    | Group(e) => obj["expression"] = e.to_json()
    SemanticAnd(code~) | SemanticNot(code~) => obj["code"] = Json(code)
    RuleRef(name~) => obj["name"] = Json(name)
    Literal(value~, ignore_case~) => {
      obj["value"] = Json(value)
      obj["ignoreCase"] = Json(ignore_case)
    }
    Class(parts~, inverted~, ignore_case~) => {
      obj["parts"] = Json(parts)
      obj["inverted"] = Json(inverted)
      obj["ignoreCase"] = Json(ignore_case)
    }
    Any => ()
  }
  if self.match_result is Some(m) {
    obj["match"] = Json(m)
  }
  Json::object(obj)
}

///|
pub impl ToJson for Initializer with fn to_json(self) {
  {
    "type": "initializer",
    "location": self.location.to_json(),
    "code": Json(self.code),
  }
}

///|
pub impl ToJson for Rule with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": "rule",
    "location": self.location.to_json(),
    "name": Json(self.name),
    "expression": self.expression.to_json(),
  }
  if self.report_failures is Some(r) {
    obj["reportFailures"] = Json(r)
  }
  if self.match_result is Some(m) {
    obj["match"] = Json(m)
  }
  if self.bytecode is Some(bc) {
    obj["bytecode"] = Json(bc)
  }
  Json::object(obj)
}

///|
pub impl ToJson for Comment with fn to_json(self) {
  {
    "text": Json(self.text),
    "multiline": Json(self.multiline),
    "location": self.location.to_json(),
  }
}

///|
pub impl ToJson for Grammar with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": "grammar",
    "location": self.location.to_json(),
    "initializer": match self.initializer {
      Some(i) => i.to_json()
      None => Json::null()
    },
    "comments": match self.comments {
      Some(cs) => {
        let m : Map[String, Json] = Map([])
        for c in cs {
          m[c.0.to_string()] = c.1.to_json()
        }
        Json::object(m)
      }
      None => Json::null()
    },
    "rules": Json(self.rules),
  }
  if self.literals is Some(xs) {
    obj["literals"] = Json(xs)
  }
  if self.classes is Some(xs) {
    obj["classes"] = Json(xs)
  }
  if self.expectations is Some(xs) {
    obj["expectations"] = Json::array(xs.map(@bytecode.expectation_const_json))
  }
  if self.functions is Some(xs) {
    obj["functions"] = Json(xs)
  }
  if self.code is Some(c) {
    obj["code"] = Json(c)
  }
  Json::object(obj)
}

///|
pub extend Node with ToJson::{to_json}

///|
pub extend Initializer with ToJson::{to_json}

///|
pub extend Rule with ToJson::{to_json}

///|
pub extend Comment with ToJson::{to_json}

///|
pub extend Grammar with ToJson::{to_json}
