%% hyperscript.pl
%%
%% Stage 1 – HyperScript language: main module and executor.
%%
%% Public API:
%%   hs_run(+Source)           – execute HyperScript source string
%%   hs_run_file(+File)        – execute a .hspl file
%%   hs_execute(+Stmts, +EnvIn, -EnvOut)  – execute statement list
%%   hs_eval(+Expr, +Env, -Value)         – evaluate an expression
%%   hs_tokenise/2, hs_parse/2            – re-exported from parser

:- module(hyperscript, [
    hs_run/1,
    hs_run_file/1,
    hs_execute/3,
    hs_eval/3,
    hs_tokenise/2,
    hs_parse/2
]).

:- use_module(hyperscript_parser).

:- discontiguous hs_eval/3.

:- reexport(hyperscript_parser, [hs_tokenise/2, hs_parse/2]).

% ---------------------------------------------------------------------------
% Top-level runners
% ---------------------------------------------------------------------------

%% hs_run(+Source)
% Parse and execute HyperScript source text.
hs_run(Source) :-
    hs_tokenise(Source, Tokens),
    hs_parse(Tokens, Stmts),
    empty_env(Env0),
    hs_execute(Stmts, Env0, _).

%% hs_run_file(+File)
% Load and execute a .hspl file.
hs_run_file(File) :-
    read_file_to_string(File, Source, []),
    hs_run(Source).

% ---------------------------------------------------------------------------
% Environment  (association list:  [VarName-Value, ...])
% ---------------------------------------------------------------------------

empty_env([]).

env_get(Env, Name, Value) :-
    memberchk(Name-Value, Env), !.
env_get(_, Name, _) :-
    format(atom(Msg), "Unbound variable: ~w", [Name]),
    throw(hs_error(unbound_variable, Msg)).

env_set([], Name, Value, [Name-Value]).
env_set([Name-_|Rest], Name, Value, [Name-Value|Rest]) :- !.
env_set([Other|Rest], Name, Value, [Other|Rest2]) :-
    env_set(Rest, Name, Value, Rest2).

% ---------------------------------------------------------------------------
% Executor
% ---------------------------------------------------------------------------

%% hs_execute(+Stmts, +EnvIn, -EnvOut)
hs_execute([], Env, Env).
hs_execute([S|Ss], Env0, EnvOut) :-
    hs_exec_one(S, Env0, Env1),
    hs_execute(Ss, Env1, EnvOut).

%% hs_exec_one(+Stmt, +EnvIn, -EnvOut)

% put Expr into Var
hs_exec_one(put(Expr, VarName), Env0, Env1) :-
    hs_eval(Expr, Env0, Val),
    env_set(Env0, VarName, Val, Env1).

% write Expr
hs_exec_one(write(Expr), Env, Env) :-
    hs_eval(Expr, Env, Val),
    hs_print_value(Val), nl.

% nl
hs_exec_one(nl, Env, Env) :- nl.

% ask Prompt giving Var
hs_exec_one(ask(Prompt, VarName), Env0, Env1) :-
    hs_eval(Prompt, Env0, PromptStr),
    write(PromptStr), flush_output,
    read_line_to_string(user_input, Line),
    env_set(Env0, VarName, Line, Env1).

% if Cond then Then else Else
hs_exec_one(if(Cond, Then, Else), Env0, EnvOut) :-
    (   hs_eval_cond(Cond, Env0)
    ->  hs_execute(Then, Env0, EnvOut)
    ;   hs_execute(Else, Env0, EnvOut)
    ).

% repeat with Var from From to To ... body
hs_exec_one(repeat_with(Var, FromExpr, ToExpr, Body), Env0, EnvOut) :-
    hs_eval(FromExpr, Env0, From),
    hs_eval(ToExpr,   Env0, To),
    hs_repeat_loop(Var, From, To, Body, Env0, EnvOut).

% Generic predicate call: call(F, Args)
hs_exec_one(call(F, ArgExprs), Env0, Env0) :-
    maplist(hs_eval_arg(Env0), ArgExprs, Args),
    Goal =.. [F|Args],
    call(Goal).

hs_eval_arg(Env, Expr, Val) :- hs_eval(Expr, Env, Val).

% Repeat helper – iterate From..To inclusive
hs_repeat_loop(_, From, To, _, Env, Env) :-
    From > To, !.
hs_repeat_loop(Var, From, To, Body, Env0, EnvOut) :-
    From =< To,
    env_set(Env0, Var, From, Env1),
    hs_execute(Body, Env1, Env2),
    Next is From + 1,
    hs_repeat_loop(Var, Next, To, Body, Env2, EnvOut).

% ---------------------------------------------------------------------------
% Condition evaluator
% ---------------------------------------------------------------------------

%% hs_eval_cond(+Cond, +Env) – succeeds iff condition is true
hs_eval_cond(cond(Op, L, R), Env) :-
    hs_eval(L, Env, LV),
    hs_eval(R, Env, RV),
    hs_apply_cond(Op, LV, RV).

hs_eval_cond(cond_not(C), Env) :-
    \+ hs_eval_cond(C, Env).

hs_eval_cond(call(true, []), _) :- !.
hs_eval_cond(call(fail, []), _) :- !, fail.
hs_eval_cond(call(false, []), _) :- !, fail.
hs_eval_cond(call(F, ArgExprs), Env) :-
    ArgExprs \= [],
    maplist(hs_eval_arg(Env), ArgExprs, Args),
    Goal =.. [F|Args],
    call(Goal).
hs_eval_cond(call(F, []), _Env) :-
    atom(F),
    Goal =.. [F],
    call(Goal).

hs_apply_cond('=',    A, B) :- A = B.
hs_apply_cond('\\=',  A, B) :- A \= B.
hs_apply_cond('==',   A, B) :- A == B.
hs_apply_cond('\\==', A, B) :- A \== B.
hs_apply_cond('=:=',  A, B) :- A =:= B.
hs_apply_cond('=\\=', A, B) :- A =\= B.
hs_apply_cond('>',    A, B) :- A > B.
hs_apply_cond('<',    A, B) :- A < B.
hs_apply_cond('>=',   A, B) :- A >= B.
hs_apply_cond('=<',   A, B) :- A =< B.
hs_apply_cond(is,     A, B) :- A =:= B.

% ---------------------------------------------------------------------------
% Expression evaluator
% ---------------------------------------------------------------------------

%% hs_eval(+Expr, +Env, -Value)

hs_eval(num(N), _, N).
hs_eval(str(S), _, S).
hs_eval(atom(A), _, A).
hs_eval(var(V), Env, Val) :- env_get(Env, V, Val).

% concat: & – string concat or list append
hs_eval(concat(E1, E2), Env, Val) :-
    hs_eval(E1, Env, V1),
    hs_eval(E2, Env, V2),
    hs_concat(V1, V2, Val).

% method chain: E >> Method
hs_eval(method_chain(E, Method), Env, Val) :-
    hs_eval(E, Env, Input),
    hs_apply_method(Method, Input, Env, Val).

% arithmetic expression
hs_eval(arith(Op, E1, E2), Env, Val) :-
    hs_eval(E1, Env, V1),
    hs_eval(E2, Env, V2),
    hs_arith(Op, V1, V2, Val).

% unary minus
hs_eval(neg(E), Env, Val) :-
    hs_eval(E, Env, V),
    Val is -V.

% list literal
hs_eval(list(Elems), Env, Val) :-
    maplist(hs_eval_list_elem(Env), Elems, Val).

hs_eval_list_elem(Env, Expr, Val) :- hs_eval(Expr, Env, Val).

% list with tail  [H1,H2|T]  – tail is already an expression
hs_eval(list_tail(Elems, TailExpr), Env, Val) :-
    maplist(hs_eval_list_elem(Env), Elems, HeadVals),
    hs_eval(TailExpr, Env, TailVal),
    append(HeadVals, TailVal, Val).

% function / predicate call as expression: returns first solution
hs_eval(call(is, [LExpr, RExpr]), Env, Val) :- !,
    hs_eval(RExpr, Env, ArithExpr),
    hs_eval_arith_expr(ArithExpr, Env, Val),
    hs_eval(LExpr, Env, Val).   % bind if LExpr is a var name string – handled
hs_eval(call(F, ArgExprs), Env, Val) :-
    maplist(hs_eval_arg(Env), ArgExprs, Args),
    Goal =.. [F, Val|Args],
    call(Goal), !.
hs_eval(call(F, ArgExprs), Env, Val) :-
    maplist(hs_eval_arg(Env), ArgExprs, Args),
    Goal =.. [F|Args],
    call(Goal), !,
    Val = true.

% method name as atom (0-arg method)
hs_eval(atom(A), _, A).

% Arithmetic evaluation of nested arith/2 terms (from tokeniser output used in
% is/2 expression position)
hs_eval_arith_expr(arith(Op, E1, E2), Env, Val) :- !,
    hs_eval_arith_expr(E1, Env, V1),
    hs_eval_arith_expr(E2, Env, V2),
    hs_arith(Op, V1, V2, Val).
hs_eval_arith_expr(neg(E), Env, Val) :- !,
    hs_eval_arith_expr(E, Env, V),
    Val is -V.
hs_eval_arith_expr(num(N), _, N) :- !.
hs_eval_arith_expr(var(V), Env, Val) :- !,
    env_get(Env, V, Val).
hs_eval_arith_expr(E, Env, Val) :-
    hs_eval(E, Env, Val).

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

hs_concat(V1, V2, Val) :-
    (   is_list(V1), is_list(V2)
    ->  append(V1, V2, Val)
    ;   hs_to_string(V1, S1), hs_to_string(V2, S2),
        string_concat(S1, S2, Val)
    ).

hs_to_string(S, S)  :- string(S), !.
hs_to_string(A, S)  :- atom(A),   !, atom_string(A, S).
hs_to_string(N, S)  :- number(N), !, number_string(N, S).
hs_to_string(V, S)  :- term_string(V, S).

hs_arith('+',  A, B, V) :- V is A + B.
hs_arith('-',  A, B, V) :- V is A - B.
hs_arith('*',  A, B, V) :- V is A * B.
hs_arith('/',  A, B, V) :- V is A / B.
hs_arith('//', A, B, V) :- V is A // B.
hs_arith('^',  A, B, V) :- V is A ^ B.
hs_arith(mod,  A, B, V) :- V is A mod B.

hs_apply_method(atom(Name), Input, Env, Val) :-
    hs_apply_method(call(Name, []), Input, Env, Val).
hs_apply_method(call(Name, ArgExprs), Input, Env, Val) :-
    maplist(hs_eval_arg(Env), ArgExprs, ExtraArgs),
    Goal =.. [Name, Input, Val|ExtraArgs],
    call(Goal), !.
hs_apply_method(call(Name, ArgExprs), Input, Env, Val) :-
    maplist(hs_eval_arg(Env), ArgExprs, ExtraArgs),
    Goal =.. [Name, Input|ExtraArgs],
    call(Goal), !,
    Val = Input.

hs_print_value(V) :-
    (string(V) -> write(V) ; print(V)).
