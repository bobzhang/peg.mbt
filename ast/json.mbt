// JSON rendering of the AST, identical in shape to the PEG.js AST objects
// (used for differential testing against the reference implementation).

///|
pub impl ToJson for Node with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": ToJson::to_json(self.type_name()),
    "location": self.location.to_json(),
  }
  match self.kind {
    Named(e, name~) => {
      obj["name"] = ToJson::to_json(name)
      obj["expression"] = e.to_json()
    }
    Choice(alternatives) => obj["alternatives"] = ToJson::to_json(alternatives)
    Action(e, code~) => {
      obj["expression"] = e.to_json()
      obj["code"] = ToJson::to_json(code)
    }
    Sequence(elements) => obj["elements"] = ToJson::to_json(elements)
    Labeled(e, label~, pick~) => {
      if pick {
        obj["pick"] = ToJson::to_json(true)
      }
      obj["label"] = match label {
        Some(l) => ToJson::to_json(l)
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
    SemanticAnd(code~) | SemanticNot(code~) =>
      obj["code"] = ToJson::to_json(code)
    RuleRef(name~) => obj["name"] = ToJson::to_json(name)
    Literal(value~, ignore_case~) => {
      obj["value"] = ToJson::to_json(value)
      obj["ignoreCase"] = ToJson::to_json(ignore_case)
    }
    Class(parts~, inverted~, ignore_case~) => {
      obj["parts"] = ToJson::to_json(parts)
      obj["inverted"] = ToJson::to_json(inverted)
      obj["ignoreCase"] = ToJson::to_json(ignore_case)
    }
    Any => ()
  }
  if self.match_result is Some(m) {
    obj["match"] = ToJson::to_json(m)
  }
  Json::object(obj)
}

///|
pub impl ToJson for Initializer with fn to_json(self) {
  {
    "type": "initializer",
    "location": self.location.to_json(),
    "code": ToJson::to_json(self.code),
  }
}

///|
pub impl ToJson for Rule with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": "rule",
    "location": self.location.to_json(),
    "name": ToJson::to_json(self.name),
    "expression": self.expression.to_json(),
  }
  if self.report_failures is Some(r) {
    obj["reportFailures"] = ToJson::to_json(r)
  }
  if self.match_result is Some(m) {
    obj["match"] = ToJson::to_json(m)
  }
  if self.bytecode is Some(bc) {
    obj["bytecode"] = ToJson::to_json(bc)
  }
  Json::object(obj)
}

///|
pub impl ToJson for Comment with fn to_json(self) {
  {
    "text": ToJson::to_json(self.text),
    "multiline": ToJson::to_json(self.multiline),
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
    "rules": ToJson::to_json(self.rules),
  }
  if self.literals is Some(xs) {
    obj["literals"] = ToJson::to_json(xs)
  }
  if self.classes is Some(xs) {
    obj["classes"] = ToJson::to_json(xs)
  }
  if self.expectations is Some(xs) {
    obj["expectations"] = Json::array(xs.map(@bytecode.expectation_const_json))
  }
  if self.functions is Some(xs) {
    obj["functions"] = ToJson::to_json(xs)
  }
  if self.code is Some(c) {
    obj["code"] = ToJson::to_json(c)
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
