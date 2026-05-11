%% hyperscript_prelude.pl
%%
%% Stage 3 – basic Prolog prelude helpers for HyperScript.

:- module(hyperscript_prelude, [
    hs_prelude_supported/2,
    hs_prelude_call/2,
    hs_prelude_eval_call/3
]).

%% hs_prelude_supported(+Name, +Arity)
% Declares the stage-3 prelude predicates currently targeted by HyperScript.
hs_prelude_supported('=', 2).
hs_prelude_supported('\\=', 2).
hs_prelude_supported('==', 2).
hs_prelude_supported('\\==', 2).
hs_prelude_supported(var, 1).
hs_prelude_supported(nonvar, 1).
hs_prelude_supported(ground, 1).
hs_prelude_supported(true, 0).
hs_prelude_supported(fail, 0).
hs_prelude_supported(false, 0).
hs_prelude_supported(!, 0).
hs_prelude_supported(once, 1).
hs_prelude_supported(call, 1).
hs_prelude_supported(not, 1).
hs_prelude_supported('\\+', 1).
hs_prelude_supported(is, 2).
hs_prelude_supported('=:=', 2).
hs_prelude_supported('=\\=', 2).
hs_prelude_supported('>', 2).
hs_prelude_supported('<', 2).
hs_prelude_supported('>=', 2).
hs_prelude_supported('=<', 2).
hs_prelude_supported(member, 2).
hs_prelude_supported(append, 3).
hs_prelude_supported(length, 2).
hs_prelude_supported(reverse, 2).
hs_prelude_supported(nth0, 3).
hs_prelude_supported(nth1, 3).
hs_prelude_supported(select, 3).
hs_prelude_supported(last, 2).
hs_prelude_supported(flatten, 2).
hs_prelude_supported(maplist, 2).
hs_prelude_supported(maplist, 3).
hs_prelude_supported(foldl, 4).
hs_prelude_supported(findall, 3).
hs_prelude_supported(bagof, 3).
hs_prelude_supported(setof, 3).
hs_prelude_supported(functor, 3).
hs_prelude_supported(arg, 3).
hs_prelude_supported('=..', 2).
hs_prelude_supported(copy_term, 2).
hs_prelude_supported(term_variables, 2).
hs_prelude_supported(atom, 1).
hs_prelude_supported(string, 1).
hs_prelude_supported(number, 1).
hs_prelude_supported(atom_string, 2).
hs_prelude_supported(number_string, 2).
hs_prelude_supported(atom_concat, 3).
hs_prelude_supported(string_concat, 3).
hs_prelude_supported(sub_string, 5).
hs_prelude_supported(split_string, 4).
hs_prelude_supported(atomic_list_concat, 2).
hs_prelude_supported(atomic_list_concat, 3).
hs_prelude_supported(write, 1).
hs_prelude_supported(writeln, 1).
hs_prelude_supported(nl, 0).
hs_prelude_supported(read, 1).
hs_prelude_supported(read_string, 2).
hs_prelude_supported(read_line_to_string, 2).
hs_prelude_supported(assertz, 1).
hs_prelude_supported(asserta, 1).
hs_prelude_supported(retract, 1).
hs_prelude_supported(retractall, 1).
hs_prelude_supported(clause, 2).
hs_prelude_supported(current_predicate, 1).

%% hs_prelude_call(+Functor, +Args)
% Generic call gateway used by HyperScript and WAM execution.
hs_prelude_call(Functor, Args) :-
    Goal =.. [Functor | Args],
    call(Goal).

%% hs_prelude_eval_call(+Functor, +Args, -Value)
% Expression-call helper:
%  1) evaluates arithmetic built-ins via is/2
%  2) tries result-last convention   F(Arg1,...,ArgN,Value)
%  3) tries result-first convention  F(Value,Arg1,...,ArgN)
%  4) falls back to predicate call and returns true
hs_prelude_eval_call(Functor, Args, Value) :-
    hs_prelude_eval_arith(Functor, Args, Value), !.
hs_prelude_eval_call(Functor, Args, Value) :-
    append(Args, [Value], CallArgs),
    Goal =.. [Functor | CallArgs],
    call(Goal), !.
hs_prelude_eval_call(Functor, Args, Value) :-
    Goal =.. [Functor, Value | Args],
    call(Goal), !.
hs_prelude_eval_call(Functor, Args, true) :-
    hs_prelude_call(Functor, Args).

% hs_prelude_eval_arith(+Functor, +Args, -Value)
% Handles arithmetic built-ins that must be computed via is/2-style evaluation,
% instead of by result-last/result-first predicate calling conventions.
hs_prelude_eval_arith(abs, [A], Value) :- Value is abs(A).
hs_prelude_eval_arith(min, [A, B], Value) :- Value is min(A, B).
hs_prelude_eval_arith(max, [A, B], Value) :- Value is max(A, B).
hs_prelude_eval_arith(round, [A], Value) :- Value is round(A).
hs_prelude_eval_arith(floor, [A], Value) :- Value is floor(A).
hs_prelude_eval_arith(ceiling, [A], Value) :- Value is ceiling(A).
hs_prelude_eval_arith(mod, [A, B], Value) :- Value is A mod B.
hs_prelude_eval_arith(rem, [A, B], Value) :- Value is rem(A, B).
