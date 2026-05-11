%% hyperscript_tests.pl
%%
%% Stage 1 + Stage 2 (WAM) + Stage 4 (REPL) + Stage 5 (delete-char)
%% + Stage 6 (line-aware tracing) + Stage 7 (error detection) tests.
%%
%% Run with:
%%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt

:- use_module(library(plunit)).
:- use_module(hyperscript).
:- use_module(hyperscript_wam).
:- use_module(hyperscript_prelude).
:- use_module(hyperscript_repl).
:- use_module(hyperscript_errors).

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
% Stage 4 – REPL tests
% ---------------------------------------------------------------------------

:- begin_tests(stage4_repl).

% --- hs_normalise_input / backspace-delete handling ---

test(normalise_no_change) :-
    hs_normalise_input("hello", Clean),
    Clean == "hello".

test(normalise_empty_string) :-
    hs_normalise_input("", Clean),
    Clean == "".

test(normalise_backspace_removes_prev) :-
    % ASCII 8 (^H / \b) removes the immediately preceding character
    string_codes(Raw, [0'h, 0'e, 0'l, 0'l, 0'p, 8, 0'o]),
    hs_normalise_input(Raw, Clean),
    Clean == "hello".

test(normalise_del_code_removes_prev) :-
    % ASCII 127 (DEL) removes the immediately preceding character
    string_codes(Raw, [0'h, 0'e, 0'l, 0'l, 0'p, 127, 0'o]),
    hs_normalise_input(Raw, Clean),
    Clean == "hello".

test(normalise_multiple_deletes) :-
    % Two consecutive DELs erase two characters
    string_codes(Raw, [0'h, 0'i, 127, 127]),
    hs_normalise_input(Raw, Clean),
    Clean == "".

test(normalise_delete_at_start_is_noop) :-
    % Delete at the very start of the buffer is silently ignored
    string_codes(Raw, [127, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

test(normalise_mixed_chars_and_deletes) :-
    % put "Hellp" <DEL> "o" → "Hello"
    string_codes(Raw, [0'p, 0'u, 0't, 0' ,
                       0'", 0'H, 0'e, 0'l, 0'l, 0'p, 127, 0'o, 0'",
                       0' , 0'i, 0'n, 0't, 0'o, 0' , 0'X]),
    hs_normalise_input(Raw, Clean),
    Clean == "put \"Hello\" into X".

test(normalise_ctrl_h_same_as_backspace) :-
    % Ctrl-H (ASCII 8) behaves identically to a regular backspace
    string_codes(Raw, [0'a, 0'b, 8, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

% --- hs_query_env : stateful environment passing ---

test(query_env_empty_initial) :-
    hs_query_env("put 99 into N", [], Solutions),
    Solutions = [Env],
    memberchk('N'-99, Env).

test(query_env_inherits_binding) :-
    % Pass an existing binding through the initial environment
    hs_query_env("put X into Y", ['X'-42], Solutions),
    Solutions = [Env],
    memberchk('Y'-42, Env).

test(query_env_member_with_initial_env) :-
    % member/2 in a REPL with a pre-populated list variable
    hs_query_env("member(E, L)", ['L'-[a,b,c]], Solutions),
    length(Solutions, 3),
    Solutions = [E1, E2, E3],
    memberchk('E'-a, E1),
    memberchk('E'-b, E2),
    memberchk('E'-c, E3).

% --- repl_print_solutions output format ---

test(print_solutions_false_when_empty, [true(Out == "false.\n")]) :-
    with_output_to(string(Out), repl_print_solutions([])).

test(print_solutions_true_when_no_bindings, [true(Out == "true.\n")]) :-
    with_output_to(string(Out), repl_print_solutions([[]])).

test(print_solutions_single_binding, [true]) :-
    with_output_to(string(Out),
        repl_print_solutions([['X'-hello]])),
    sub_string(Out, _, _, _, "X = hello"),
    sub_string(Out, _, _, _, ".").

test(print_solutions_multi_shows_semicolon, [true]) :-
    with_output_to(string(Out),
        repl_print_solutions([['X'-a], ['X'-b], ['X'-c]])),
    sub_string(Out, _, _, _, "X = a"),
    sub_string(Out, _, _, _, "X = b"),
    sub_string(Out, _, _, _, "X = c"),
    sub_string(Out, _, _, _, ";"),
    sub_string(Out, _, _, _, "false.").

test(print_solutions_two_vars_in_one_solution, [true]) :-
    with_output_to(string(Out),
        repl_print_solutions([['X'-1, 'Y'-2]])),
    sub_string(Out, _, _, _, "X = 1"),
    sub_string(Out, _, _, _, "Y = 2").

% --- repl_format_bindings ---

test(format_bindings_empty_is_noop) :-
    with_output_to(string(Out), repl_format_bindings([])),
    Out == "".

test(format_bindings_one_pair, [true]) :-
    with_output_to(string(Out), repl_format_bindings(['A'-99])),
    sub_string(Out, _, _, _, "A = 99").

% --- REPL command dispatch (non-interactive, unit-testable) ---

test(repl_command_help_prints_help, [true]) :-
    repl_init,
    with_output_to(string(Out), repl_command(":help")),
    sub_string(Out, _, _, _, ":quit"),
    sub_string(Out, _, _, _, ":trace").

test(repl_command_trace_on) :-
    repl_init,
    repl_command(":trace on"),
    repl_get(trace, on).

test(repl_command_trace_off) :-
    repl_init,
    repl_set(trace, on),
    repl_command(":trace off"),
    repl_get(trace, off).

test(repl_command_clear_empties_env) :-
    repl_init,
    repl_set(env, ['X'-1]),
    repl_command(":clear"),
    repl_get(env, []).

test(repl_command_starlog_method_chain) :-
    repl_init,
    repl_command(":starlog method_chain"),
    repl_get(starlog_style, method_chain).

test(repl_command_starlog_nested) :-
    repl_init,
    repl_command(":starlog nested"),
    repl_get(starlog_style, nested).

test(repl_command_starlog_compressed) :-
    repl_init,
    repl_command(":starlog compressed"),
    repl_get(starlog_style, compressed).

test(repl_env_shows_bindings, [true]) :-
    repl_init,
    repl_set(env, ['X'-hello]),
    with_output_to(string(Out), repl_command(":env")),
    sub_string(Out, _, _, _, "X = hello").

% --- End-to-end dispatch via repl_dispatch ---

test(dispatch_empty_line_is_noop) :-
    repl_init,
    repl_dispatch("").

test(dispatch_put_updates_env) :-
    repl_init,
    repl_dispatch("put 7 into N"),
    repl_get(env, Env),
    memberchk('N'-7, Env).

test(dispatch_write_produces_output, [true]) :-
    repl_init,
    with_output_to(string(Out),
        repl_dispatch("write \"hello\"")),
    sub_string(Out, _, _, _, "hello").

test(dispatch_member_query, [true]) :-
    repl_init,
    with_output_to(string(Out),
        repl_dispatch("member(X,[a,b,c])")),
    sub_string(Out, _, _, _, "X = a"),
    sub_string(Out, _, _, _, "X = b"),
    sub_string(Out, _, _, _, "X = c"),
    sub_string(Out, _, _, _, "false.").

test(dispatch_fail_query, [true(Out == "false.\n")]) :-
    repl_init,
    with_output_to(string(Out), repl_dispatch("fail")).

% --- Block depth detection ---

test(block_depth_single_line_put) :-
    repl_block_depth("put 1 into X", 0).

test(block_depth_open_repeat) :-
    repl_block_depth("repeat with I from 1 to 3", 1).

test(block_depth_closed_repeat) :-
    repl_block_depth("repeat with I from 1 to 3\nwrite I\nend repeat", 0).

test(block_depth_open_if) :-
    repl_block_depth("if X = 1 then write yes", 1).

test(block_depth_closed_if) :-
    repl_block_depth("if X = 1 then write yes\nend if", 0).

:- end_tests(stage4_repl).

% ---------------------------------------------------------------------------
% Stage 5 – Delete character support
% ---------------------------------------------------------------------------
%
% Tests for hs_normalise_input/2 covering all required forms:
%   • ASCII 8   (^H / Ctrl-H / Backspace)
%   • ASCII 127 (DEL)
%   • Visible two-character sequences ^H and ^? (terminal echo artefacts)
%   • Unicode SYMBOL FOR BACKSPACE  U+2408
%   • Unicode SYMBOL FOR DELETE     U+2421
%   • The pr1.txt acceptance test: put "Hellp" <DEL> "o" into X → "Hello"
%
% ---------------------------------------------------------------------------

:- begin_tests(stage5_delete_char).

% --- ASCII backspace (8, Ctrl-H) ---

test(s5_backspace_removes_prev) :-
    % ASCII 8 removes the immediately preceding character
    string_codes(Raw, [0'h, 0'e, 0'l, 0'l, 0'p, 8, 0'o]),
    hs_normalise_input(Raw, Clean),
    Clean == "hello".

test(s5_ctrl_h_same_as_backspace) :-
    % ASCII 8 (Ctrl-H) is identical to a standard backspace
    string_codes(Raw, [0'a, 0'b, 8, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

test(s5_backspace_at_start_is_noop) :-
    % Backspace at the very beginning of the buffer is silently ignored
    string_codes(Raw, [8, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

% --- ASCII DEL (127) ---

test(s5_del_removes_prev) :-
    % ASCII 127 (DEL) removes the immediately preceding character
    string_codes(Raw, [0'h, 0'e, 0'l, 0'l, 0'p, 127, 0'o]),
    hs_normalise_input(Raw, Clean),
    Clean == "hello".

test(s5_del_at_start_is_noop) :-
    % DEL at the very beginning of the buffer is silently ignored
    string_codes(Raw, [127, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

test(s5_multiple_dels_erase_multiple_chars) :-
    % Two consecutive DELs erase two characters
    string_codes(Raw, [0'h, 0'i, 127, 127]),
    hs_normalise_input(Raw, Clean),
    Clean == "".

% --- Visible control sequences (terminal echo artefacts) ---

test(s5_visible_caret_H_acts_as_backspace) :-
    % The two-character sequence "^H" (0x5E 0x48) is a common terminal artefact
    % for Ctrl-H and must be treated as a single backspace.
    string_codes(Raw, [0'a, 0'b, 0'^, 0'H, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

test(s5_visible_caret_question_acts_as_del) :-
    % The two-character sequence "^?" (0x5E 0x3F) is the visible echo of DEL
    % and must be treated as a single delete.
    string_codes(Raw, [0'a, 0'b, 0'^, 0'?, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

test(s5_visible_caret_H_at_start_is_noop) :-
    % ^H at the start of the buffer deletes nothing
    string_codes(Raw, [0'^, 0'H, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

test(s5_visible_caret_question_at_start_is_noop) :-
    % ^? at the start of the buffer deletes nothing
    string_codes(Raw, [0'^, 0'?, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

% --- Unicode delete symbols ---

test(s5_unicode_symbol_backspace_removes_prev) :-
    % U+2408 SYMBOL FOR BACKSPACE (code point 9224) removes the preceding char
    string_codes(Raw, [0'a, 0'b, 9224, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

test(s5_unicode_symbol_delete_removes_prev) :-
    % U+2421 SYMBOL FOR DELETE (code point 9249) removes the preceding char
    string_codes(Raw, [0'a, 0'b, 9249, 0'c]),
    hs_normalise_input(Raw, Clean),
    Clean == "ac".

test(s5_unicode_symbol_backspace_at_start_is_noop) :-
    % U+2408 at the very start of the buffer is silently ignored
    string_codes(Raw, [9224, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

test(s5_unicode_symbol_delete_at_start_is_noop) :-
    % U+2421 at the very start of the buffer is silently ignored
    string_codes(Raw, [9249, 0'h, 0'i]),
    hs_normalise_input(Raw, Clean),
    Clean == "hi".

% --- Mixed forms ---

test(s5_mixed_ascii_and_unicode_deletes) :-
    % Mix ASCII 127 and U+2421 – both must erase one character each
    string_codes(Raw, [0'a, 0'b, 0'c, 127, 9249]),
    hs_normalise_input(Raw, Clean),
    Clean == "a".

test(s5_mixed_backspace_and_visible_caret_H) :-
    % Mix ASCII 8 and visible ^H – both must erase one character each
    string_codes(Raw, [0'a, 0'b, 8, 0'c, 0'^, 0'H, 0'd]),
    hs_normalise_input(Raw, Clean),
    Clean == "ad".

% --- pr1.txt acceptance test ---

test(s5_acceptance_put_hellp_del_o) :-
    % pr1.txt stage-5 acceptance test:
    %   Typing  put "Hellp" <DEL> "o" into X  must yield  put "Hello" into X
    % which the parser then evaluates to  X = "Hello".
    string_codes(Raw, [0'p, 0'u, 0't, 0' ,
                       0'", 0'H, 0'e, 0'l, 0'l, 0'p, 127, 0'o, 0'",
                       0' , 0'i, 0'n, 0't, 0'o, 0' , 0'X]),
    hs_normalise_input(Raw, Clean),
    Clean == "put \"Hello\" into X".

test(s5_acceptance_executes_correctly) :-
    % End-to-end: normalise the raw input then execute it; X must be "Hello"
    string_codes(Raw, [0'p, 0'u, 0't, 0' ,
                       0'", 0'H, 0'e, 0'l, 0'l, 0'p, 127, 0'o, 0'",
                       0' , 0'i, 0'n, 0't, 0'o, 0' , 0'X]),
    hs_normalise_input(Raw, Clean),
    hs_tokenise(Clean, Tokens),
    hs_parse(Tokens, Stmts),
    hs_execute(Stmts, [], Env),
    memberchk('X'-"Hello", Env).

% --- No-op cases ---

test(s5_no_deletes_string_unchanged) :-
    hs_normalise_input("hello world", Clean),
    Clean == "hello world".

test(s5_empty_string_unchanged) :-
    hs_normalise_input("", Clean),
    Clean == "".

:- end_tests(stage5_delete_char).

% ---------------------------------------------------------------------------
% Stage 6 – Line-aware tracing with full I/O
% ---------------------------------------------------------------------------
%
% Tests for:
%   hs_trace_source(+Source)   – trace HyperScript source
%   hs_trace_file(+File)       – trace a .hspl file
%   hs_trace_query(+Query)     – trace a source string (query form)
%   hs_set_trace(+on_or_off)   – global trace toggle
%
% Trace output format (per step):
%   [line N] CALL <readable op>
%   [line N] IO write(<val>)   (write instructions)
%   [line N] IO read(<var>)    (ask instructions)
%   [line N] CP+ (count: N)    (choice-point created)
%   [line N] CP- (count: N)    (choice-point removed / backtrack)
%   [line N] REDO              (re-entering after backtrack)
%   [line N] EXIT <Name = Val | true>
%   [line N] FAIL
%   [trace]  halt | fail
%   [bindings] Name = Val
% ---------------------------------------------------------------------------

:- begin_tests(stage6_trace).

% hs_set_trace/1 -------------------------------------------------------

test(s6_set_trace_on_off) :-
    hs_set_trace(on),
    hs_set_trace(off).   % cleanup – must not throw

% hs_trace_source/1 – basic structure ----------------------------------

test(s6_trace_source_produces_output) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X")),
    Out \= "".

test(s6_trace_source_shows_call) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X")),
    sub_string(Out, _, _, _, "CALL").

test(s6_trace_source_shows_line_number) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X")),
    sub_string(Out, _, _, _, "[line 1]").

test(s6_trace_source_shows_two_line_numbers) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X\nput 2 into Y")),
    sub_string(Out, _, _, _, "[line 1]"),
    sub_string(Out, _, _, _, "[line 2]").

test(s6_trace_source_shows_exit) :-
    with_output_to(string(Out),
        hs_trace_source("put 42 into N")),
    sub_string(Out, _, _, _, "EXIT").

test(s6_trace_source_shows_halt) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X")),
    sub_string(Out, _, _, _, "halt").

% Variable bindings on EXIT -------------------------------------------

test(s6_trace_source_shows_new_binding) :-
    with_output_to(string(Out),
        hs_trace_source("put \"Hello\" into X")),
    sub_string(Out, _, _, _, "X").

test(s6_trace_source_exit_shows_var_value) :-
    with_output_to(string(Out),
        hs_trace_source("put 99 into N")),
    ( sub_string(Out, _, _, _, "N = 99")
    ; sub_string(Out, _, _, _, "[bindings] N = 99")
    ).

test(s6_trace_source_final_bindings) :-
    with_output_to(string(Out),
        hs_trace_source("put \"Hello\" into X")),
    sub_string(Out, _, _, _, "[bindings]").

% IO events -----------------------------------------------------------

test(s6_trace_source_io_write_event) :-
    with_output_to(string(Out),
        hs_trace_source("write \"test\"")),
    sub_string(Out, _, _, _, "IO").

test(s6_trace_source_io_write_shows_value) :-
    with_output_to(string(Out),
        hs_trace_source("write \"hello\"")),
    sub_string(Out, _, _, _, "IO write"),
    sub_string(Out, _, _, _, "hello").

test(s6_trace_source_io_write_variable) :-
    with_output_to(string(Out),
        hs_trace_source("put 42 into N\nwrite N")),
    sub_string(Out, _, _, _, "IO write"),
    sub_string(Out, _, _, _, "42").

% Readable CALL format ------------------------------------------------

test(s6_trace_call_contains_put) :-
    with_output_to(string(Out),
        hs_trace_source("put 1 into X")),
    sub_string(Out, _, _, _, "put").

test(s6_trace_call_contains_write) :-
    with_output_to(string(Out),
        hs_trace_source("write hello")),
    sub_string(Out, _, _, _, "write").

% FAIL path -----------------------------------------------------------

test(s6_trace_source_does_not_throw) :-
    % Ensure tracing completes without throwing for a simple program
    with_output_to(string(_Out),
        hs_trace_source("put 1 into X")).

test(s6_trace_source_fail_produces_fail_event) :-
    % A call to fail/0 should produce a FAIL trace event
    with_output_to(string(Out),
        hs_trace_source("fail")),
    sub_string(Out, _, _, _, "FAIL").

% Repeat loop tracing -------------------------------------------------

test(s6_trace_source_repeat_shows_multiple_calls) :-
    with_output_to(string(Out),
        hs_trace_source("repeat with I from 1 to 3\nwrite I\nend repeat")),
    sub_string(Out, _, _, _, "CALL"),
    sub_string(Out, _, _, _, "IO write").

% hs_trace_file/1 -----------------------------------------------------

test(s6_trace_file_traces_file, [setup(setup_trace_file(F)),
                                  cleanup(delete_file(F))]) :-
    with_output_to(string(Out), hs_trace_file(F)),
    sub_string(Out, _, _, _, "CALL"),
    sub_string(Out, _, _, _, "[line 1]").

setup_trace_file(File) :-
    tmp_file(hs_trace_test, File),
    open(File, write, S),
    write(S, "put 7 into X\n"),
    close(S).

% hs_trace_query/1 ----------------------------------------------------

test(s6_trace_query_shows_call) :-
    with_output_to(string(Out),
        hs_trace_query("put 5 into N")),
    sub_string(Out, _, _, _, "CALL").

test(s6_trace_query_shows_exit) :-
    with_output_to(string(Out),
        hs_trace_query("put 5 into N")),
    sub_string(Out, _, _, _, "EXIT").

test(s6_trace_query_shows_line_number) :-
    with_output_to(string(Out),
        hs_trace_query("put 5 into N")),
    sub_string(Out, _, _, _, "[line 1]").

:- end_tests(stage6_trace).

% ---------------------------------------------------------------------------
% Stage 7 – Error detection
% ---------------------------------------------------------------------------
%
% Tests for:
%   hs_check_source(+Source, -Errors)   – detect errors in source
%   hs_check_tokens(+Tokens, -Errors)   – detect token-level errors
%   hs_check_ast(+AST, -Errors)         – detect AST-level errors
%   hs_print_error(+Error)              – pretty-print a single error
%   hs_format_error(+Error, -Str)       – format error as string
%   hs_runtime_error(+PrologErr, -Err)  – wrap a caught Prolog error
%
% Error term:  hs_error(Type, Msg, File, Line, Col, Source, Hint)
% ---------------------------------------------------------------------------

:- begin_tests(stage7_errors).

% ---------------------------------------------------------------------------
% hs_print_error / hs_format_error
% ---------------------------------------------------------------------------

test(s7_print_error_contains_type, [true]) :-
    Err = hs_error(syntax_error, "test message", '', 0, 0, '', ''),
    with_output_to(string(Out), hs_print_error(Err)),
    sub_string(Out, _, _, _, "syntax_error").

test(s7_print_error_contains_message, [true]) :-
    Err = hs_error(type_error, "bad type here", '', 0, 0, '', ''),
    with_output_to(string(Out), hs_print_error(Err)),
    sub_string(Out, _, _, _, "bad type here").

test(s7_print_error_shows_hint, [true]) :-
    Err = hs_error(missing_then, "msg", '', 3, 0, '', "add then"),
    with_output_to(string(Out), hs_print_error(Err)),
    sub_string(Out, _, _, _, "add then").

test(s7_print_error_shows_line, [true]) :-
    Err = hs_error(syntax_error, "msg", '', 5, 0, '', ''),
    with_output_to(string(Out), hs_print_error(Err)),
    sub_string(Out, _, _, _, "5").

test(s7_print_error_shows_file, [true]) :-
    Err = hs_error(syntax_error, "msg", 'test.hspl', 1, 0, '', ''),
    with_output_to(string(Out), hs_print_error(Err)),
    sub_string(Out, _, _, _, "test.hspl").

test(s7_format_error_returns_string, [true]) :-
    Err = hs_error(domain_error, "bad value", '', 0, 0, '', ''),
    hs_format_error(Err, Str),
    string(Str),
    sub_string(Str, _, _, _, "domain_error").

% ---------------------------------------------------------------------------
% hs_check_source – clean source produces no errors
% ---------------------------------------------------------------------------

test(s7_clean_source_no_errors) :-
    hs_check_source("put 42 into N", Errors),
    Errors == [].

test(s7_clean_multiline_no_errors) :-
    hs_check_source("put 1 into X\nwrite X", Errors),
    Errors == [].

test(s7_clean_if_no_errors) :-
    hs_check_source("if X = 1 then write ok end if", Errors),
    Errors == [].

test(s7_clean_repeat_no_errors) :-
    hs_check_source("repeat with I from 1 to 3\nwrite I\nend repeat", Errors),
    Errors == [].

% ---------------------------------------------------------------------------
% hs_check_source – unterminated string detection
% ---------------------------------------------------------------------------

test(s7_unterminated_string_detected, [true]) :-
    hs_check_source("put \"hello into X", Errors),
    Errors \= [],
    Errors = [hs_error(Type, _, _, _, _, _, _)|_],
    Type == unterminated_string.

test(s7_terminated_string_no_error) :-
    hs_check_source("put \"hello\" into X", Errors),
    Errors == [].

% ---------------------------------------------------------------------------
% hs_check_source – missing structural tokens
% ---------------------------------------------------------------------------

test(s7_missing_end_repeat_detected, [true]) :-
    hs_check_source("repeat with I from 1 to 3\nwrite I", Errors),
    Errors \= [],
    member(hs_error(missing_end_repeat, _, _, _, _, _, _), Errors).

test(s7_closed_repeat_no_error) :-
    hs_check_source("repeat with I from 1 to 3\nwrite I\nend repeat", Errors),
    Errors == [].

% ---------------------------------------------------------------------------
% hs_check_ast – unknown predicate detection
% ---------------------------------------------------------------------------

test(s7_unknown_predicate_in_call, [true]) :-
    hs_tokenise("blarg_xyz(1,2,3)", Tokens),
    hs_parse(Tokens, AST),
    hs_check_ast(AST, Errors),
    Errors \= [],
    member(hs_error(unknown_predicate, _, _, _, _, _, _), Errors).

test(s7_known_predicate_no_error) :-
    hs_tokenise("member(X, [a,b])", Tokens),
    hs_parse(Tokens, AST),
    hs_check_ast(AST, Errors),
    \+ member(hs_error(unknown_predicate, _, _, _, _, _, _), Errors).

% ---------------------------------------------------------------------------
% hs_check_ast – singleton variable detection
% ---------------------------------------------------------------------------

test(s7_singleton_variable_detected, [true]) :-
    % Y is used twice (put + write), so no singleton warning expected
    hs_tokenise("put 1 into Y\nwrite Y", Tokens),
    hs_parse(Tokens, AST),
    hs_check_singletons(AST, Errors),
    Errors == [].

test(s7_singleton_single_occurrence, [true]) :-
    % OnlyOnce is used only in the put, so it is a singleton
    hs_tokenise("put OnlyOnce into Y", Tokens),
    hs_parse(Tokens, AST),
    hs_check_singletons(AST, Errors),
    Errors \= [],
    member(hs_error(singleton_variable, _, _, _, _, _, _), Errors).

test(s7_underscore_prefix_not_singleton) :-
    % _Ignored is intentionally unused; must NOT produce a singleton warning
    hs_tokenise("put 1 into _Ignored", Tokens),
    hs_parse(Tokens, AST),
    hs_check_singletons(AST, Errors),
    \+ member(hs_error(singleton_variable, _, _, _, _, _, _), Errors).

% ---------------------------------------------------------------------------
% hs_runtime_error – wrapping caught Prolog errors
% ---------------------------------------------------------------------------

test(s7_runtime_instantiation_error, [true]) :-
    hs_runtime_error(error(instantiation_error, context(_, _)),
                     hs_error(instantiation_error, _, _, _, _, _, _)).

test(s7_runtime_type_error_evaluable, [true]) :-
    hs_runtime_error(error(type_error(evaluable, foo/0), _),
                     hs_error(unbound_variable, _, _, _, _, _, _)).

test(s7_runtime_type_error_general, [true]) :-
    hs_runtime_error(error(type_error(integer, foo), _),
                     hs_error(type_error, _, _, _, _, _, _)).

test(s7_runtime_domain_error, [true]) :-
    hs_runtime_error(error(domain_error(not_less_than_zero, -1), _),
                     hs_error(domain_error, _, _, _, _, _, _)).

test(s7_runtime_permission_error, [true]) :-
    hs_runtime_error(error(permission_error(modify, static_procedure, foo/1), _),
                     hs_error(permission_error, _, _, _, _, _, _)).

test(s7_runtime_existence_error, [true]) :-
    hs_runtime_error(error(existence_error(procedure, bar/2), _),
                     hs_error(unknown_predicate, _, _, _, _, _, _)).

test(s7_runtime_hs_unbound, [true]) :-
    hs_runtime_error(hs_error(unbound_variable, "Unbound variable: X"),
                     hs_error(unbound_variable, _, _, _, _, _, _)).

test(s7_runtime_unknown_wraps_generic, [true]) :-
    hs_runtime_error(some_unknown_error,
                     hs_error(runtime_error, _, _, _, _, _, _)).

% ---------------------------------------------------------------------------
% hs_conversion_error
% ---------------------------------------------------------------------------

test(s7_conversion_error_to_starlog, [true]) :-
    hs_conversion_error(to_starlog, "unsupported construct",
                        hs_error(conversion_error_to, _, _, _, _, _, _)).

test(s7_conversion_error_from_starlog, [true]) :-
    hs_conversion_error(from_starlog, "invalid token",
                        hs_error(conversion_error_from, _, _, _, _, _, _)).

% ---------------------------------------------------------------------------
% hs_check_ast – invalid assignment target
% ---------------------------------------------------------------------------

test(s7_invalid_assignment_number_target, [true]) :-
    % Manually construct an AST with a non-atom assignment target
    AST = [put(num(1), 42)],   % 42 is not an atom variable name
    hs_check_ast(AST, Errors),
    Errors \= [],
    member(hs_error(invalid_assignment, _, _, _, _, _, _), Errors).

test(s7_valid_assignment_atom_target) :-
    AST = [put(num(1), 'MyVar')],
    hs_check_ast(AST, Errors),
    \+ member(hs_error(invalid_assignment, _, _, _, _, _, _), Errors).

% ---------------------------------------------------------------------------
% hs_check_source – complete round-trip (no errors for valid programs)
% ---------------------------------------------------------------------------

test(s7_roundtrip_arithmetic_no_errors) :-
    hs_check_source("put 3 + 4 into N", Errors),
    Errors == [].

test(s7_roundtrip_list_no_errors) :-
    hs_check_source("put [1,2,3] into L", Errors),
    Errors == [].

test(s7_roundtrip_method_chain_no_errors) :-
    hs_check_source("put X >> reverse into N", Errors),
    \+ member(hs_error(malformed_chain, _, _, _, _, _, _), Errors).

:- end_tests(stage7_errors).

% ---------------------------------------------------------------------------
% Test runner entry point
%
% The built-in plunit run_tests/0 is used:
%   swipl -q -s hyperscript_tests.pl -g run_tests -t halt
% ---------------------------------------------------------------------------
