#!/usr/bin/env bash
# Regenerates every generated file of the port from the reference PEG.js
# implementation (pinned below). Requires node (25.x: the Unicode case
# tables are captured from its V8) and moon.
#
#   tools/regenerate.sh && git diff --exit-code
set -euo pipefail
cd "$(dirname "$0")/.."

PEGJS_REPO=https://github.com/pegjs/pegjs
PEGJS_COMMIT=b7b87ea8aeeaa1caf096e2da99fd95a971890ca1

if [ ! -d .repos/pegjs/.git ]; then
  git init -q .repos/pegjs
  git -C .repos/pegjs remote add origin "$PEGJS_REPO"
fi
if [ "$(git -C .repos/pegjs rev-parse HEAD 2>/dev/null)" != "$PEGJS_COMMIT" ]; then
  git -C .repos/pegjs fetch -q --depth 1 origin "$PEGJS_COMMIT"
  git -C .repos/pegjs checkout -q FETCH_HEAD
fi

(cd tools && npm ci --no-audit --no-fund --loglevel=error)
ln -sfn ../../.repos/pegjs/packages/pegjs tools/node_modules/pegjs

# Record the upstream test suite's interactions with PEG.js.
(cd .repos/pegjs &&
  HARVEST_OUT=../../tools/corpus.jsonl NODE_PATH=../../tools/node_modules \
    ../../tools/node_modules/.bin/mocha --reporter dot \
    --require ../../tools/harvest.js 'test/**/*.spec.js')

node tools/gen-unicode.js > runtime/unicode_tables.mbt
node tools/gen-case-fixtures.js > runtime/case_fixture_test.mbt
node tools/gen-program.js .repos/pegjs/src/parser.pegjs meta_program \
  '{"features":{"offset":false,"range":false,"expected":false}}' > parser/meta_program.mbt
node tools/gen-meta-source.js > parser/meta_grammar_source.mbt
node tools/gen-fixtures.js
node tools/gen-self-host.js

moon build --target native cmd/pegmbt
pegmbt=_build/native/debug/build/cmd/pegmbt/pegmbt.exe
"$pegmbt" examples/arithmetics/arithmetics.pegjs
"$pegmbt" examples/json/json.pegjs
"$pegmbt" internal/self_host/parser.pegjs --value-type Meta
"$pegmbt" internal/codegen_regress/regress.pegjs --name-prefix speed_ -o internal/codegen_regress/speed_parser.mbt
"$pegmbt" internal/codegen_regress/regress.pegjs --name-prefix size_ -O size -o internal/codegen_regress/size_parser.mbt
node tools/gen-codegen-corpus.js

moon fmt
moon info
