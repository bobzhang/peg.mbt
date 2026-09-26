// JSON rendering of the AST, identical in shape to the PEG.js AST objects
// (used for differential testing against the reference implementation).

///|
pub impl ToJson for Node with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": self.type_name().to_json(),
    "location": self.location.to_json(),
  }
  match self.kind {
    Named(e, name~) => {
      obj["name"] = name.to_json()
      obj["expression"] = e.to_json()
    }
    Choice(alternatives) => obj["alternatives"] = alternatives.to_json()
    Action(e, code~) => {
      obj["expression"] = e.to_json()
      obj["code"] = code.to_json()
    }
    Sequence(elements) => obj["elements"] = elements.to_json()
    Labeled(e, label~, pick~) => {
      if pick {
        obj["pick"] = true.to_json()
      }
      obj["label"] = match label {
        Some(l) => l.to_json()
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
    SemanticAnd(code~) | SemanticNot(code~) => obj["code"] = code.to_json()
    RuleRef(name~) => obj["name"] = name.to_json()
    Literal(value~, ignore_case~) => {
      obj["value"] = value.to_json()
      obj["ignoreCase"] = ignore_case.to_json()
    }
    Class(parts~, inverted~, ignore_case~) => {
      obj["parts"] = parts.to_json()
      obj["inverted"] = inverted.to_json()
      obj["ignoreCase"] = ignore_case.to_json()
    }
    Any => ()
  }
  if self.match_result is Some(m) {
    obj["match"] = m.to_json()
  }
  Json::object(obj)
}

///|
pub impl ToJson for Initializer with fn to_json(self) {
  {
    "type": "initializer",
    "location": self.location.to_json(),
    "code": self.code.to_json(),
  }
}

///|
pub impl ToJson for Rule with fn to_json(self) {
  let obj : Map[String, Json] = {
    "type": "rule",
    "location": self.location.to_json(),
    "name": self.name.to_json(),
    "expression": self.expression.to_json(),
  }
  if self.report_failures is Some(r) {
    obj["reportFailures"] = r.to_json()
  }
  if self.match_result is Some(m) {
    obj["match"] = m.to_json()
  }
  if self.bytecode is Some(bc) {
    obj["bytecode"] = bc.to_json()
  }
  Json::object(obj)
}

///|
pub impl ToJson for Comment with fn to_json(self) {
  {
    "text": self.text.to_json(),
    "multiline": self.multiline.to_json(),
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
    "rules": self.rules.to_json(),
  }
  if self.literals is Some(xs) {
    obj["literals"] = xs.to_json()
  }
  if self.classes is Some(xs) {
    obj["classes"] = xs.to_json()
  }
  if self.expectations is Some(xs) {
    obj["expectations"] = Json::array(xs.map(@bytecode.expectation_const_json))
  }
  if self.functions is Some(xs) {
    obj["functions"] = xs.to_json()
  }
  if self.code is Some(c) {
    obj["code"] = c.to_json()
  }
  Json::object(obj)
}
