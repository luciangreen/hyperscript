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
| `hyperscript_tests.pl` | PLUnit test suite |
| `examples/hyperscript_basic.hspl` | Example script |
