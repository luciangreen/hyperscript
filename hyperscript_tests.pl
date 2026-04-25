%% hyperscript_tests.pl
%%
%% Stage 1 tests for the HyperScript language layer.
%%
%% Run with:
%%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt

:- use_module(library(plunit)).
:- use_module(hyperscript).

% ---------------------------------------------------------------------------
% Tokeniser tests
% ---------------------------------------------------------------------------

:- begin_tests(tokeniser).

test(number_integer) :-
    hs_tokenise("42", [number(42)]).

test(number_float) :-
    hs_tokenise("3.14", [number(N)]),
    abs(N - 3.14) < 0.001.

test(string) :-
    hs_tokenise("\"hello\"", [string("hello")]).

test(string_with_escape) :-
    hs_tokenise("\"a\\nb\"", [string(S)]),
    string_codes(S, [0'a, 0'\n, 0'b]).

test(variable) :-
    hs_tokenise("MyVar", [var('MyVar')]).

test(underscore_var) :-
    hs_tokenise("_X", [var('_X')]).

test(keyword_put) :-
    hs_tokenise("put", [kw(put)]).

test(keyword_into) :-
    hs_tokenise("into", [kw(into)]).

test(atom) :-
    hs_tokenise("foo", [atom(foo)]).

test(operator_amp) :-
    hs_tokenise("&", [op('&')]).

test(operator_method_chain) :-
    hs_tokenise(">>", [op('>>') ]).

test(operator_eq) :-
    hs_tokenise("=", [op('=')]).

test(operator_arith_eq) :-
    hs_tokenise("=:=", [op('=:=')]).

test(full_put_statement) :-
    hs_tokenise("put \"hello\" into X",
        [kw(put), string("hello"), kw(into), var('X')]).

test(list_tokens) :-
    hs_tokenise("[1,2]",
        [punct('['), number(1), punct(','), number(2), punct(']')]).

test(comment_skipped) :-
    hs_tokenise("% this is a comment\nfoo", [atom(foo)]).

:- end_tests(tokeniser).

% ---------------------------------------------------------------------------
% Parser tests
% ---------------------------------------------------------------------------

:- begin_tests(parser).

test(parse_put) :-
    hs_tokenise("put \"hello\" into X", T),
    hs_parse(T, [put(str("hello"), 'X')]).

test(parse_write) :-
    hs_tokenise("write X", T),
    hs_parse(T, [write(var('X'))]).

test(parse_nl) :-
    hs_tokenise("nl", T),
    hs_parse(T, [nl]).

test(parse_arithmetic_expr) :-
    hs_tokenise("put 2 + 3 into N", T),
    hs_parse(T, [put(arith('+', num(2), num(3)), 'N')]).

test(parse_concat) :-
    hs_tokenise("put X & Y into Z", T),
    hs_parse(T, [put(concat(var('X'), var('Y')), 'Z')]).

test(parse_if_then_else) :-
    hs_tokenise("if X = 1 then write ok else write fail end if", T),
    hs_parse(T, [if(cond('=', var('X'), num(1)),
                    [write(atom(ok))],
                    [write(atom(fail))])]).

test(parse_if_then_no_else) :-
    hs_tokenise("if X = 1 then write ok end if", T),
    hs_parse(T, [if(cond('=', var('X'), num(1)),
                    [write(atom(ok))],
                    [])]).

test(parse_repeat) :-
    hs_tokenise("repeat with I from 1 to 3 write I end repeat", T),
    hs_parse(T, [repeat_with('I', num(1), num(3), [write(var('I'))])]).

test(parse_list_literal) :-
    hs_tokenise("put [1,2,3] into L", T),
    hs_parse(T, [put(list([num(1),num(2),num(3)]), 'L')]).

test(parse_method_chain) :-
    hs_tokenise("put X >> atom_length into N", T),
    hs_parse(T, [put(method_chain(var('X'), atom(atom_length)), 'N')]).

test(parse_predicate_call) :-
    hs_tokenise("foo(1,2)", T),
    hs_parse(T, [call(foo, [num(1), num(2)])]).

:- end_tests(parser).

% ---------------------------------------------------------------------------
% Execution tests  (use with_output_to to capture writes)
% ---------------------------------------------------------------------------

:- begin_tests(execution).

exec(Source, EnvOut) :-
    hs_tokenise(Source, T),
    hs_parse(T, Stmts),
    hs_execute(Stmts, [], EnvOut).

exec_output(Source, Output) :-
    with_output_to(string(Output), exec(Source, _)).

test(put_and_lookup) :-
    exec("put 42 into N", Env),
    memberchk('N'-42, Env).

test(put_string) :-
    exec("put \"hello\" into S", Env),
    memberchk('S'-"hello", Env).

test(write_number, [true(Output == "42\n")]) :-
    exec_output("put 42 into N\nwrite N", Output).

test(write_string, [true(Output == "hello\n")]) :-
    exec_output("write \"hello\"", Output).

test(string_concat, [true(Output == "hello world\n")]) :-
    exec_output("put \"hello\" & \" world\" into Y\nwrite Y", Output).

test(arithmetic_add) :-
    exec("put 3 + 4 into N", Env),
    memberchk('N'-7, Env).

test(arithmetic_multiply) :-
    exec("put 6 * 7 into N", Env),
    memberchk('N'-42, Env).

test(arithmetic_mixed) :-
    exec("put (10 + 5) * 2 into N", Env),
    memberchk('N'-30, Env).

test(if_then_true, [true(Output == "yes\n")]) :-
    exec_output("put 1 into X\nif X = 1 then write yes else write no end if",
                Output).

test(if_then_false, [true(Output == "no\n")]) :-
    exec_output("put 2 into X\nif X = 1 then write yes else write no end if",
                Output).

test(repeat_loop, [true(Output == "1\n2\n3\n")]) :-
    exec_output("repeat with I from 1 to 3\nwrite I\nend repeat", Output).

test(list_concat) :-
    exec("put [1,2] & [3,4] into L", Env),
    memberchk('L'-[1,2,3,4], Env).

test(nl_output, [true(Output == "\n")]) :-
    exec_output("nl", Output).

test(predicate_call) :-
    exec_output("write hello", Output),
    Output == "hello\n".

:- end_tests(execution).

% ---------------------------------------------------------------------------
% Test runner entry point
%
% The built-in plunit run_tests/0 is used:
%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt
% ---------------------------------------------------------------------------
