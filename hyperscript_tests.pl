%% hyperscript_tests.pl
%%
%% Stage 1 + Stage 2 (WAM) tests for HyperScript.
%%
%% Run with:
%%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt

:- use_module(library(plunit)).
:- use_module(hyperscript).
:- use_module(hyperscript_wam).
:- use_module(hyperscript_prelude).

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
% Stage 3 prelude tests
% ---------------------------------------------------------------------------

:- begin_tests(stage3_prelude).

test(prelude_registry_contains_core_predicates) :-
    hs_prelude_supported(member, 2),
    hs_prelude_supported(append, 3),
    hs_prelude_supported(length, 2),
    hs_prelude_supported(atom_string, 2),
    hs_prelude_supported(assertz, 1).

test(expr_call_length_result_last) :-
    exec("put length([a,b,c]) into N", Env),
    memberchk('N'-3, Env).

test(expr_call_reverse_result_last) :-
    exec("put reverse([1,2,3]) into R", Env),
    memberchk('R'-[3,2,1], Env).

test(expr_call_atom_concat_result_last) :-
    exec("put atom_concat('hello','world') into A", Env),
    memberchk('A'-helloworld, Env).

test(expr_call_number_string_result_last) :-
    exec("put number_string(42) into S", Env),
    memberchk('S'-"42", Env).

test(expr_call_abs_arithmetic) :-
    exec("put abs(-5) into N", Env),
    memberchk('N'-5, Env).

test(expr_call_min_arithmetic) :-
    exec("put min(10,3) into N", Env),
    memberchk('N'-3, Env).

test(expr_call_max_arithmetic) :-
    exec("put max(10,3) into N", Env),
    memberchk('N'-10, Env).

test(expr_call_round_arithmetic) :-
    exec("put round(3.6) into N", Env),
    memberchk('N'-4, Env).

test(expr_call_floor_arithmetic) :-
    exec("put floor(3.6) into N", Env),
    memberchk('N'-3, Env).

test(expr_call_ceiling_arithmetic) :-
    exec("put ceiling(3.1) into N", Env),
    memberchk('N'-4, Env).

test(expr_call_mod_arithmetic) :-
    exec("put mod(10,3) into N", Env),
    memberchk('N'-1, Env).

test(expr_call_rem_arithmetic) :-
    exec("put rem(10,3) into N", Env),
    memberchk('N'-1, Env).

test(query_append_backtracks_three_solutions) :-
    hs_query("append(X,Y,[a,b])", Solutions),
    length(Solutions, 3),
    Solutions = [E1, E2, E3],
    memberchk('X'-[], E1),
    memberchk('Y'-[a,b], E1),
    memberchk('X'-[a], E2),
    memberchk('Y'-[b], E2),
    memberchk('X'-[a,b], E3),
    memberchk('Y'-[], E3).

test(query_nonvar_after_put) :-
    hs_query("put 1 into X\nnonvar(X)", Solutions),
    Solutions = [Env],
    memberchk('X'-1, Env).

:- end_tests(stage3_prelude).

% ---------------------------------------------------------------------------
% WAM compiler tests
% ---------------------------------------------------------------------------

:- begin_tests(wam_compiler).

test(compile_put) :-
    hs_compile("put 42 into N", Bytecode),
    Bytecode = [wam_instr(1, hs_put(num(42), 'N')), wam_instr(0, proceed)].

test(compile_write) :-
    hs_compile("write X", Bytecode),
    Bytecode = [wam_instr(1, hs_write(var('X'))), wam_instr(0, proceed)].

test(compile_nl) :-
    hs_compile("nl", Bytecode),
    Bytecode = [wam_instr(1, hs_nl), wam_instr(0, proceed)].

test(compile_if) :-
    hs_compile("if X = 1 then write yes else write no end if", Bytecode),
    Bytecode = [wam_instr(1, hs_if(cond('=', var('X'), num(1)),
                                   [wam_instr(1, hs_write(atom(yes)))],
                                   [wam_instr(1, hs_write(atom(no)))])),
                wam_instr(0, proceed)].

test(compile_repeat) :-
    hs_compile("repeat with I from 1 to 3\nwrite I\nend repeat", Bytecode),
    Bytecode = [wam_instr(1, hs_repeat('I', num(1), num(3),
                                       [wam_instr(1, hs_write(var('I')))])),
                wam_instr(0, proceed)].

test(compile_multiple_stmts) :-
    hs_compile("put 1 into A\nput 2 into B", Bytecode),
    Bytecode = [wam_instr(1, hs_put(num(1), 'A')),
                wam_instr(2, hs_put(num(2), 'B')),
                wam_instr(0, proceed)].

:- end_tests(wam_compiler).

% ---------------------------------------------------------------------------
% WAM run_bc tests (step machine)
% ---------------------------------------------------------------------------

:- begin_tests(wam_run_bc).

wam_exec(Source, Env) :-
    hs_compile(Source, Bytecode),
    hs_run_bc(Bytecode, Env).

wam_exec_output(Source, Output) :-
    with_output_to(string(Output), wam_exec(Source, _)).

test(put_number) :-
    wam_exec("put 42 into N", Env),
    memberchk('N'-42, Env).

test(put_string) :-
    wam_exec("put \"hello\" into S", Env),
    memberchk('S'-"hello", Env).

test(put_arithmetic) :-
    wam_exec("put 3 + 4 into N", Env),
    memberchk('N'-7, Env).

test(put_multiply) :-
    wam_exec("put 6 * 7 into N", Env),
    memberchk('N'-42, Env).

test(put_concat) :-
    wam_exec("put \"hello\" & \" world\" into S", Env),
    memberchk('S'-"hello world", Env).

test(write_number, [true(Out == "42\n")]) :-
    wam_exec_output("put 42 into N\nwrite N", Out).

test(write_string, [true(Out == "hello\n")]) :-
    wam_exec_output("write \"hello\"", Out).

test(if_true, [true(Out == "yes\n")]) :-
    wam_exec_output(
        "put 1 into X\nif X = 1 then write yes else write no end if",
        Out).

test(if_false, [true(Out == "no\n")]) :-
    wam_exec_output(
        "put 2 into X\nif X = 1 then write yes else write no end if",
        Out).

test(repeat_loop, [true(Out == "1\n2\n3\n")]) :-
    wam_exec_output(
        "repeat with I from 1 to 3\nwrite I\nend repeat",
        Out).

test(repeat_empty_range, [true(Out == "")]) :-
    wam_exec_output(
        "repeat with I from 5 to 3\nwrite I\nend repeat",
        Out).

test(wam_state_done_halt) :-
    wam_initial_state([wam_instr(0, proceed)], S0),
    hs_step(S0, S1),
    wam_state_done(S1).

test(wam_initial_heap_empty) :-
    wam_initial_state([], wam(H, 0, E, [], [], [], run)),
    empty_assoc(H),
    empty_assoc(E).

:- end_tests(wam_run_bc).

% ---------------------------------------------------------------------------
% WAM unification tests
% ---------------------------------------------------------------------------

:- begin_tests(wam_unification).

:- use_module(hyperscript_wam,
        [wam_initial_state/2, hs_step/2, wam_state_done/1]).

test(unify_constants) :-
    empty_assoc(H0),
    hyperscript_wam:heap_alloc(H0, 0, const(hello), A1, H1, 1),
    hyperscript_wam:heap_alloc(H1, 1, const(hello), A2, H2, 2),
    hyperscript_wam:wam_unify(H2, [], A1, A2, _, _).

test(unify_constants_fail, [fail]) :-
    empty_assoc(H0),
    hyperscript_wam:heap_alloc(H0, 0, const(hello), A1, H1, 1),
    hyperscript_wam:heap_alloc(H1, 1, const(world), A2, H2, 2),
    hyperscript_wam:wam_unify(H2, [], A1, A2, _, _).

test(unify_var_with_const) :-
    empty_assoc(H0),
    hyperscript_wam:heap_alloc(H0, 0, unbound(0), A1, H1, 1),
    hyperscript_wam:heap_alloc(H1, 1, const(hello), A2, H2, 2),
    hyperscript_wam:wam_unify(H2, [], A1, A2, H3, Trail),
    hyperscript_wam:heap_to_prolog(H3, A1, hello),
    Trail = [0].

test(unify_two_vars) :-
    empty_assoc(H0),
    hyperscript_wam:heap_alloc(H0, 0, unbound(0), A1, H1, 1),
    hyperscript_wam:heap_alloc(H1, 1, unbound(1), A2, H2, 2),
    hyperscript_wam:wam_unify(H2, [], A1, A2, H3, _),
    % After unification one variable references the other (check raw heap cells)
    hyperscript_wam:heap_get(H3, A1, C1raw),
    hyperscript_wam:heap_get(H3, A2, C2raw),
    ( C1raw = ref(_) ; C2raw = ref(_) ).

test(undo_trail) :-
    empty_assoc(H0),
    hyperscript_wam:heap_alloc(H0, 0, unbound(0), A1, H1, 1),
    hyperscript_wam:heap_alloc(H1, 1, const(42), A2, H2, 2),
    hyperscript_wam:wam_unify(H2, [], A1, A2, H3, Trail),
    hyperscript_wam:heap_to_prolog(H3, A1, 42),
    hyperscript_wam:wam_undo_trail(H3, Trail, H4),
    hyperscript_wam:heap_get(H4, A1, unbound(A1)).

:- end_tests(wam_unification).

% ---------------------------------------------------------------------------
% WAM query tests (meta-interpreter, backtracking)
% ---------------------------------------------------------------------------

:- begin_tests(wam_query).

test(query_put) :-
    hs_query("put 42 into N", Solutions),
    Solutions = [Env],
    memberchk('N'-42, Env).

test(query_write_output, [true(Out == "hello\n")]) :-
    with_output_to(string(Out),
        hs_query("write \"hello\"", _)).

test(query_if_true) :-
    hs_query("put 1 into X\nif X = 1 then put yes into R else put no into R end if",
             Solutions),
    Solutions = [Env],
    memberchk('R'-yes, Env).

test(query_member_backtrack) :-
    hs_query("member(X, [a,b,c])", Solutions),
    length(Solutions, 3),
    Solutions = [Env1, Env2, Env3],
    memberchk('X'-a, Env1),
    memberchk('X'-b, Env2),
    memberchk('X'-c, Env3).

test(query_no_solutions, [true(Solutions == [])]) :-
    hs_query("fail", Solutions).

test(query_arithmetic) :-
    hs_query("put 10 + 5 into N", Solutions),
    Solutions = [Env],
    memberchk('N'-15, Env).

test(query_repeat) :-
    with_output_to(string(Out),
        hs_query("repeat with I from 1 to 3\nwrite I\nend repeat", _)),
    Out == "1\n2\n3\n".

:- end_tests(wam_query).

% ---------------------------------------------------------------------------
% WAM step tests
% ---------------------------------------------------------------------------

:- begin_tests(wam_step).

test(step_proceed) :-
    wam_initial_state([wam_instr(1, proceed)], S0),
    hs_step(S0, S1),
    wam_state_done(S1),
    S1 = wam(_, _, _, _, _, _, halt).

test(step_fail_no_cp) :-
    wam_initial_state([wam_instr(1, fail)], S0),
    hs_step(S0, S1),
    wam_state_done(S1),
    S1 = wam(_, _, _, _, _, _, fail).

test(step_try_me_else_success) :-
    % try_me_else pushes a choice point; on success proceed halts
    Bytecode = [wam_instr(1, try_me_else([wam_instr(1, fail)])),
                wam_instr(1, proceed)],
    wam_initial_state(Bytecode, S0),
    hs_step(S0, S1),        % execute try_me_else → cp pushed
    hs_step(S1, S2),        % execute proceed → halt
    wam_state_done(S2),
    S2 = wam(_, _, _, _, _, _, halt).

test(step_backtrack_to_alt) :-
    % fail triggers backtrack to alternative
    AltCode = [wam_instr(1, proceed)],
    Bytecode = [wam_instr(1, try_me_else(AltCode)),
                wam_instr(1, fail)],
    wam_initial_state(Bytecode, S0),
    hs_step(S0, S1),        % try_me_else → cp pushed
    hs_step(S1, S2),        % fail → backtrack
    % S2 should now be running AltCode
    S2 = wam(_, _, _, _, _, AltCode, run).

test(step_cut_clears_cps) :-
    AltCode = [wam_instr(1, fail)],
    Bytecode = [wam_instr(1, try_me_else(AltCode)),
                wam_instr(1, cut),
                wam_instr(1, proceed)],
    wam_initial_state(Bytecode, S0),
    hs_step(S0, S1),  % try_me_else
    hs_step(S1, S2),  % cut → CPs = []
    S2 = wam(_, _, _, [], _, _, run).

test(step_hs_put) :-
    wam_initial_state([wam_instr(1, hs_put(num(99), 'X')), wam_instr(0, proceed)], S0),
    hs_step(S0, S1),
    S1 = wam(H, _, Env, _, _, _, run),
    get_assoc('X', Env, Addr),
    hyperscript_wam:heap_to_prolog(H, Addr, 99).

:- end_tests(wam_step).

% ---------------------------------------------------------------------------
% WAM trace test
% ---------------------------------------------------------------------------

:- begin_tests(wam_trace).

test(trace_produces_output) :-
    with_output_to(string(Out),
        hs_trace("put 1 into X")),
    sub_string(Out, _, _, _, "CALL").

test(trace_shows_line_numbers) :-
    with_output_to(string(Out),
        hs_trace("put 42 into N\nwrite N")),
    sub_string(Out, _, _, _, "[line 1]"),
    sub_string(Out, _, _, _, "[line 2]").

test(trace_shows_halt) :-
    with_output_to(string(Out),
        hs_trace("put 1 into X")),
    sub_string(Out, _, _, _, "halt").

:- end_tests(wam_trace).

% ---------------------------------------------------------------------------
% Test runner entry point
%
% The built-in plunit run_tests/0 is used:
%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt
% ---------------------------------------------------------------------------
