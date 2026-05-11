# hyperscript

Runs and converts between HyperScript and Prolog.

HyperScript is a HyperCard-inspired scripting language that compiles to and from Prolog / compressed Starlog.

---

## Stage 1 – HyperScript language

### What is HyperScript?

HyperScript is a readable, English-like scripting layer built on SWI-Prolog.
It supports variables, strings, atoms, numbers, lists, arithmetic, conditional
execution, loops, and direct Prolog predicate calls.

### Syntax overview

```
put "hello" into X
put X & " world" into Y
write Y

put 6 into A
put 7 into B
put A * B into C
write C

repeat with I from 1 to 10
    write I
end repeat

ask "Name? " giving Name
write Name

if X = "yes" then
    write "Correct!"
else
    write "Incorrect."
end if
```

### Supported constructs

| Construct | Example |
|-----------|---------|
| Assignment | `put "hello" into X` |
| Write | `write X` |
| Newline | `nl` |
| Input | `ask "Prompt" giving Var` |
| If / then / else | `if X = 1 then write ok else write no end if` |
| Repeat loop | `repeat with I from 1 to 10 … end repeat` |
| Predicate call | `member(X, [a,b,c])` |
| String concat | `put X & " world" into Y` |
| List concat | `put [1,2] & [3,4] into L` |
| Arithmetic | `put (10 + 5) * 2 into N` |
| Method chain | `put X >> atom_length into N` |

### Arithmetic operators

`+`, `-`, `*`, `/`, `//` (integer div), `^` (power)

### Condition operators

`=`, `\=`, `==`, `\==`, `=:=`, `=\=`, `>`, `<`, `>=`, `=<`, `is`

---

## Stage 3 – Basic Prolog prelude

HyperScript now includes a stage-3 prelude module (`hyperscript_prelude.pl`) and
routes generic calls through it.

Supported categories include:
- unification/control (`=`, `\\=`, `==`, `\\==`, `var/1`, `nonvar/1`, `ground/1`, `once/1`, `call/1`, `not/1`, `\\+/1`)
- arithmetic predicates (`is/2`, `=:=/2`, `=\\=/2`, `>/2`, `</2`, `>=/2`, `=</2`)
- list predicates (`member/2`, `append/3`, `length/2`, `reverse/2`, `nth0/3`, `nth1/3`, `select/3`, `last/2`, `flatten/2`)
- term predicates (`functor/3`, `arg/3`, `=../2`, `copy_term/2`, `term_variables/2`)
- atom/string/number predicates (`atom/1`, `string/1`, `number/1`, `atom_string/2`, `number_string/2`, `atom_concat/3`, `string_concat/3`)
- I/O and dynamic database predicates (`write/1`, `writeln/1`, `nl/0`, `assertz/1`, `asserta/1`, `retract/1`, `retractall/1`, `clause/2`, `current_predicate/1`)

Expression-call evaluation now supports result-last style automatically, e.g.:

```prolog
put length([a,b,c]) into N
put atom_concat('hello','world') into A
put number_string(42) into S
put abs(-5) into V
```

---

## Stage 8 – Starlog conversion

HyperScript now supports two-way conversion with:

```prolog
hs_to_starlog(+HyperScriptSource, +Options, -StarlogSource).
starlog_to_hs(+StarlogSource, +Options, -HyperScriptSource).
```

Supported options:
- `compressed(true|false)`
- `style(method_chain|nested|compressed)` (`compressed` style is an alias for `method_chain`)
- `preserve_comments(true|false)`
- `trace(true|false)`

Example:

```prolog
?- hs_to_starlog("put \"Hello\" & \"World\" into X",
                 [compressed(true), style(method_chain)],
                 S).
S = "starlog_call(X is \"Hello\":\"World\").".
```

```prolog
?- starlog_to_hs("string_concat(\"Hello\",\"World\",X).",
                 [style(nested)],
                 HS).
HS = "put \"Hello\" & \"World\" into X".
```

---

## Running HyperScript files

```sh
swipl -q -s hyperscript.pl -g "hs_run_file('examples/hyperscript_basic.hspl')" -t halt
```

---

## API

```prolog
:- use_module(hyperscript).

% Execute HyperScript source text
hs_run(+Source)

% Execute a .hspl file
hs_run_file(+File)

% Execute a list of parsed statements with an environment
hs_execute(+Stmts, +EnvIn, -EnvOut)

% Evaluate a HyperScript expression
hs_eval(+Expr, +Env, -Value)

% Tokenise source text
hs_tokenise(+Source, -Tokens)

% Parse token list to AST
hs_parse(+Tokens, -Statements)
```

---

## Running tests

```sh
swipl -q -s hyperscript_tests.pl -g run_tests -t halt
```

Tests cover the tokeniser, parser, and executor.

---

## Files

| File | Purpose |
|------|---------|
| `hyperscript.pl` | Main module – executor and top-level runners |
| `hyperscript_parser.pl` | Tokeniser (`hs_tokenise/2`) and parser (`hs_parse/2`) |
| `hyperscript_starlog_convert.pl` | Stage-8 HyperScript ↔ Starlog conversion |
| `hyperscript_tests.pl` | PLUnit test suite |
| `examples/hyperscript_basic.hspl` | Example script |
