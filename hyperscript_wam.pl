%% hyperscript_wam.pl
%%
%% Stage 2 – WAM-style execution engine for HyperScript.
%%
%% The WAM models:
%%   heap              – assoc(Addr:int -> wam_cell)
%%   environment       – assoc(VarName:atom -> Addr:int)
%%   choice-point stack – list of cp(AltPending, SaveHTop, SaveEnv, SaveTrail)
%%   trail             – list of Addr:int  (bindings to undo on backtrack)
%%   unification       – WAM-style with trail recording
%%   backtracking      – choice-point pop + trail undo
%%   predicate frames  – via environment + continuation code (Pending list)
%%   cut               – discard choice points
%%   variable bindings – heap cells (unbound/ref/const/struc/cons/nil)
%%   line mapping      – statement index encoded in wam_instr(Line, Op)
%%
%% Public API:
%%   hs_compile(+Source, -Bytecode)    compile HyperScript source to bytecode
%%   hs_run_bc(+Bytecode, -Env)        run bytecode, return final bindings
%%   hs_query(+Source, -Solutions)     compile + run, collecting all solutions
%%   hs_step(+State0, -State1)         single WAM step
%%   hs_trace(+Source)                 compile and execute with trace output
%%   hs_compile_ast(+AST, -Bytecode)   compile already-parsed AST
%%   wam_initial_state(+Bytecode, -State)
%%   wam_state_done(+State)

:- module(hyperscript_wam, [
    hs_compile/2,
    hs_run_bc/2,
    hs_query/2,
    hs_query_env/3,
    hs_step/2,
    hs_trace/1,
    hs_trace_source/1,
    hs_trace_file/1,
    hs_trace_query/1,
    hs_set_trace/1,
    hs_compile_ast/2,
    wam_initial_state/2,
    wam_state_done/1,
    % Exported for tests
    heap_alloc/6,
    heap_get/3,
    heap_deref/4,
    heap_to_prolog/3,
    wam_unify/6,
    wam_undo_trail/3
]).

:- use_module(library(assoc)).
:- use_module(hyperscript_parser, [hs_tokenise/2, hs_parse/2]).
:- use_module(hyperscript_prelude, [hs_prelude_call/2]).
:- use_module(hyperscript,
        [ hs_eval/3, hs_eval_cond/2, hs_apply_cond/3,
          hs_print_value/1, hs_concat/3, hs_arith/4, hs_apply_method/4 ]).

:- discontiguous wam_exec_instr/3.

% ===========================================================================
% WAM State
%
%   wam(Heap, HTop, Env, CPStack, Trail, Pending, Status)
%
%   Heap     : assoc(Addr:int -> wam_cell)
%   HTop     : int   – next free heap address (0-based)
%   Env      : assoc(VarName:atom -> Addr:int)
%   CPStack  : list of cp(AltPending, SaveHTop, SaveEnv, SaveTrail)
%   Trail    : list of Addr:int
%   Pending  : list of wam_instr(Line:int, Op)   – remaining instructions
%   Status   : run | halt | fail | error(Msg)
%
% Heap cell types:
%   unbound(Addr)              – unbound variable; self-referential
%   ref(Addr)                  – bound; points to Addr
%   const(Value)               – atomic (atom / number / string)
%   struc(Functor, Arity, ArgAddrs)
%   cons(HeadAddr, TailAddr)   – list cons cell
%   nil                        – empty list []
% ===========================================================================

wam_initial_state(Code, wam(H, 0, E, [], [], Code, run)) :-
    empty_assoc(H),
    empty_assoc(E).

wam_state_done(wam(_, _, _, _, _, _, Status)) :-
    Status \= run.

% ===========================================================================
% 1. Heap operations
% ===========================================================================

%% heap_alloc(+H0, +HTop, +Cell, -Addr, -H1, -HTop1)
heap_alloc(H0, HTop, Cell, HTop, H1, HTop1) :-
    put_assoc(HTop, H0, Cell, H1),
    HTop1 is HTop + 1.

%% heap_get(+H, +Addr, -Cell)
heap_get(H, Addr, Cell) :- get_assoc(Addr, H, Cell).

%% heap_put(+H0, +Addr, +Cell, -H1)
heap_put(H0, Addr, Cell, H1) :- put_assoc(Addr, H0, Cell, H1).

%% heap_deref(+H, +Addr, -FinalAddr, -Cell)
% Follow ref chains to the ultimate (unbound or non-ref) cell.
heap_deref(H, Addr, FA, FC) :-
    heap_get(H, Addr, C),
    (   C = ref(Next), Next \= Addr
    ->  heap_deref(H, Next, FA, FC)
    ;   FA = Addr, FC = C
    ).

% ===========================================================================
% 2. Trail and bind
% ===========================================================================

%% wam_bind(+H0, +Trail0, +Addr, +Cell, -H1, -Trail1)
% Bind the unbound variable at Addr to Cell, recording Addr on Trail.
wam_bind(H0, Trail0, Addr, Cell, H1, Trail1) :-
    heap_put(H0, Addr, Cell, H1),
    Trail1 = [Addr | Trail0].

%% wam_undo_trail(+H0, +Trail, -H1)
% Reset all addresses in Trail back to unbound cells.
wam_undo_trail(H, [], H).
wam_undo_trail(H0, [Addr | Rest], H2) :-
    heap_put(H0, Addr, unbound(Addr), H1),
    wam_undo_trail(H1, Rest, H2).

% ===========================================================================
% 3. Unification
% ===========================================================================

%% wam_unify(+H0, +Trail0, +Addr1, +Addr2, -H1, -Trail1)
% Unify two heap addresses; fail if they are incompatible.
wam_unify(H0, T0, A1, A2, H1, T1) :-
    heap_deref(H0, A1, DA1, C1),
    heap_deref(H0, A2, DA2, C2),
    wam_unify_cells(H0, T0, DA1, C1, DA2, C2, H1, T1).

% Both already the same address → trivially equal
wam_unify_cells(H, T, Addr, _, Addr, _, H, T) :- !.
% First is unbound, second is also unbound → bind A1 to ref(A2)
wam_unify_cells(H0, T0, A1, unbound(_), A2, unbound(_), H1, T1) :- !,
    wam_bind(H0, T0, A1, ref(A2), H1, T1).
% First is unbound, second is concrete → bind A1 to C2
wam_unify_cells(H0, T0, A1, unbound(_), _A2, C2, H1, T1) :- !,
    wam_bind(H0, T0, A1, C2, H1, T1).
% Second is unbound, first is concrete → bind A2 to C1
wam_unify_cells(H0, T0, _A1, C1, A2, unbound(_), H1, T1) :- !,
    wam_bind(H0, T0, A2, C1, H1, T1).
% Constants
wam_unify_cells(H, T, _, const(V), _, const(V), H, T) :- !.
% Nil
wam_unify_cells(H, T, _, nil, _, nil, H, T) :- !.
% Structures (same functor + arity)
wam_unify_cells(H0, T0, _, struc(F, N, As1), _, struc(F, N, As2), H1, T1) :- !,
    wam_unify_arg_list(H0, T0, As1, As2, H1, T1).
% List cons cells
wam_unify_cells(H0, T0, _, cons(HH1, HT1), _, cons(HH2, HT2), H2, T2) :- !,
    wam_unify(H0, T0, HH1, HH2, H1, T1),
    wam_unify(H1, T1, HT1, HT2, H2, T2).
% Mismatch → fail
wam_unify_cells(_, _, _, _, _, _, _, _) :- fail.

wam_unify_arg_list(H, T, [], [], H, T).
wam_unify_arg_list(H0, T0, [A1|As1], [A2|As2], H2, T2) :-
    wam_unify(H0, T0, A1, A2, H1, T1),
    wam_unify_arg_list(H1, T1, As1, As2, H2, T2).

% ===========================================================================
% 4. Heap <-> Prolog term conversion
% ===========================================================================

%% heap_to_prolog(+H, +Addr, -Term)
heap_to_prolog(H, Addr, Term) :-
    heap_deref(H, Addr, _, Cell),
    cell_to_prolog(H, Cell, Term).

cell_to_prolog(_, unbound(A), '$unbound'(A)) :- !.
cell_to_prolog(_, const(V), V) :- !.
cell_to_prolog(_, nil, []) :- !.
cell_to_prolog(H, cons(HA, TA), [Head | Tail]) :- !,
    heap_to_prolog(H, HA, Head),
    heap_to_prolog(H, TA, Tail).
cell_to_prolog(H, struc(F, _A, ArgAs), Term) :- !,
    maplist(heap_to_prolog(H), ArgAs, Args),
    Term =.. [F | Args].
cell_to_prolog(_, ref(A), '$ref'(A)).   % should not arise after deref

%% prolog_to_heap(+H0, +HTop0, +Trail0, +Term, -Addr, -H1, -HTop1, -Trail1)
% Allocate a Prolog term on the WAM heap; return its address.
prolog_to_heap(H0, HTop, Trail, V, Addr, H1, HTop1, Trail) :-
    ( atom(V) ; number(V) ; string(V) ),
    V \= [],   % [] is an atom in Prolog but maps to the nil cell
    !,
    heap_alloc(H0, HTop, const(V), Addr, H1, HTop1).
prolog_to_heap(H0, HTop, Trail, [], Addr, H1, HTop1, Trail) :- !,
    heap_alloc(H0, HTop, nil, Addr, H1, HTop1).
prolog_to_heap(H0, HTop0, Trail0, [Head | Tail], Addr, H3, HTop3, Trail3) :- !,
    prolog_to_heap(H0,  HTop0,  Trail0,  Head, HA, H1, HTop1, Trail1),
    prolog_to_heap(H1,  HTop1,  Trail1,  Tail, TA, H2, HTop2, Trail2),
    heap_alloc(H2, HTop2, cons(HA, TA), Addr, H3, HTop3),
    Trail3 = Trail2.
prolog_to_heap(H0, HTop0, Trail0, Term, Addr, H2, HTop2, Trail2) :-
    compound(Term), !,
    Term =.. [F | Args],
    length(Args, A),
    maplist_prolog_to_heap(H0, HTop0, Trail0, Args, ArgAs, H1, HTop1, Trail1),
    heap_alloc(H1, HTop1, struc(F, A, ArgAs), Addr, H2, HTop2),
    Trail2 = Trail1.
% Fallback for unbound variables or other terms
prolog_to_heap(H0, HTop, Trail, _V, Addr, H1, HTop1, Trail) :-
    heap_alloc(H0, HTop, unbound(HTop), Addr, H1, HTop1).

maplist_prolog_to_heap(H, HT, Tr, [], [], H, HT, Tr).
maplist_prolog_to_heap(H0, HT0, Tr0, [A|As], [Addr|Addrs], H2, HT2, Tr2) :-
    prolog_to_heap(H0, HT0, Tr0, A, Addr, H1, HT1, Tr1),
    maplist_prolog_to_heap(H1, HT1, Tr1, As, Addrs, H2, HT2, Tr2).

% ===========================================================================
% 5. WAM env <-> HyperScript env conversion
% ===========================================================================

%% wam_env_to_hs(+WamEnv:assoc, +Heap, -HsEnv:list(Name-Val))
% Convert the WAM assoc environment to a HyperScript association list.
wam_env_to_hs(WamEnv, Heap, HsEnv) :-
    assoc_to_list(WamEnv, Pairs),
    maplist(wam_pair_to_hs(Heap), Pairs, HsEnv).

wam_pair_to_hs(Heap, Name-Addr, Name-Val) :-
    heap_to_prolog(Heap, Addr, Val).

%% wam_env_put(+Env0, +Name, +Val, +H0, +HTop0, +Trail0,
%%             -Env1, -H1, -HTop1, -Trail1)
% Store a Prolog value in the WAM env (allocating on the heap).
wam_env_put(Env0, Name, Val, H0, HTop0, Trail0,
            Env1, H1, HTop1, Trail1) :-
    prolog_to_heap(H0, HTop0, Trail0, Val, Addr, H1, HTop1, Trail1),
    put_assoc(Name, Env0, Addr, Env1).

% ===========================================================================
% 6. Compiler: HyperScript source / AST -> WAM bytecode
% ===========================================================================
%
% Bytecode = list of wam_instr(Line, Op)
%
% Op types (high-level HyperScript ops):
%   hs_put(Expr, VarName)               put Expr into VarName
%   hs_write(Expr)                      write Expr
%   hs_nl                               nl
%   hs_ask(PromptExpr, VarName)         ask Prompt giving VarName
%   hs_if(Cond, ThenCode, ElseCode)     if/then/else  (inline sub-bytecodes)
%   hs_repeat(Var, FromExpr, ToExpr, BodyCode)
%   hs_call(F, ArgExprs)                generic predicate call
%
% Low-level WAM control ops:
%   try_me_else(AltPending)             push choice point
%   cut                                 discard choice points
%   fail                                explicit failure
%   proceed                             halt successfully
% ===========================================================================

%% hs_compile(+Source, -Bytecode)
hs_compile(Source, Bytecode) :-
    hs_tokenise(Source, Tokens),
    hs_parse(Tokens, Stmts),
    hs_compile_ast(Stmts, Bytecode).

%% hs_compile_ast(+Stmts, -Bytecode)
hs_compile_ast(Stmts, Bytecode) :-
    compile_stmts(Stmts, 1, Body),
    append(Body, [wam_instr(0, proceed)], Bytecode).

compile_stmts([], _, []).
compile_stmts([S | Ss], N, Instrs) :-
    compile_stmt(S, N, SInstrs),
    N1 is N + 1,
    compile_stmts(Ss, N1, RestInstrs),
    append(SInstrs, RestInstrs, Instrs).

compile_stmt(put(Expr, Var), N,
    [wam_instr(N, hs_put(Expr, Var))]).

compile_stmt(write(Expr), N,
    [wam_instr(N, hs_write(Expr))]).

compile_stmt(nl, N,
    [wam_instr(N, hs_nl)]).

compile_stmt(ask(Prompt, Var), N,
    [wam_instr(N, hs_ask(Prompt, Var))]).

compile_stmt(call(F, Args), N,
    [wam_instr(N, hs_call(F, Args))]).

compile_stmt(if(Cond, Then, Else), N,
    [wam_instr(N, hs_if(Cond, ThenCode, ElseCode))]) :-
    compile_stmts(Then, N, ThenCode),
    compile_stmts(Else, N, ElseCode).

compile_stmt(repeat_with(Var, From, To, Body), N,
    [wam_instr(N, hs_repeat(Var, From, To, BodyCode))]) :-
    compile_stmts(Body, N, BodyCode).

% ===========================================================================
% 7. WAM step machine
% ===========================================================================

%% hs_step(+State0, -State1)
% Execute one WAM instruction; handle backtracking if the step fails.
hs_step(wam(H, HTop, Env, CPs, Trail, [Instr | Rest], run), State1) :- !,
    State_next = wam(H, HTop, Env, CPs, Trail, Rest, run),
    (   catch(wam_exec_instr(Instr, State_next, State1),
              _Err,
              wam_backtrack(State_next, State1))
    ->  true
    ;   wam_backtrack(State_next, State1)
    ).
hs_step(wam(H, HTop, Env, CPs, Trail, [], run), State1) :-
    wam_backtrack(wam(H, HTop, Env, CPs, Trail, [], run), State1).

%% wam_backtrack(+State0, -State1)
% Pop the top choice point and continue with its alternative pending code.
wam_backtrack(wam(H0, _HT, _Env, [cp(AltPending, SaveHTop, SaveEnv, SaveTrail) | CPs],
                  Trail, _, run),
              wam(H1, SaveHTop, SaveEnv, CPs, SaveTrail, AltPending, run)) :- !,
    wam_undo_trail(H0, Trail, H1).
wam_backtrack(wam(H, HTop, Env, [], Trail, _, run),
              wam(H, HTop, Env, [], Trail, [], fail)).

% ===========================================================================
% 8. Instruction execution
% ===========================================================================

%% wam_exec_instr(+Instr, +StateIn, -StateOut)
% StateIn has Instr already removed from Pending.

% --- proceed ---
wam_exec_instr(wam_instr(_, proceed),
               wam(H, HTop, Env, CPs, Trail, _, run),
               wam(H, HTop, Env, CPs, Trail, [], halt)) :- !.

% --- fail ---
wam_exec_instr(wam_instr(_, fail), State0, State1) :- !,
    wam_backtrack(State0, State1).

% --- cut ---
% Discard all choice points created since the current continuation began.
wam_exec_instr(wam_instr(_, cut),
               wam(H, HTop, Env, _CPs, Trail, Rest, run),
               wam(H, HTop, Env, [], Trail, Rest, run)) :- !.

% --- try_me_else(AltPending) ---
% Push a choice point; continue with the current pending code.
wam_exec_instr(wam_instr(_, try_me_else(AltPending)),
               wam(H, HTop, Env, CPs, Trail, Rest, run),
               wam(H, HTop, Env,
                   [cp(AltPending, HTop, Env, Trail) | CPs],
                   Trail, Rest, run)) :- !.

% --- hs_put(Expr, VarName) ---
wam_exec_instr(wam_instr(_, hs_put(Expr, VarName)),
               wam(H0, HTop0, Env0, CPs, Trail0, Rest, run),
               wam(H1, HTop1, Env1, CPs, Trail1, Rest, run)) :- !,
    wam_env_to_hs(Env0, H0, HsEnv),
    hs_eval(Expr, HsEnv, Val),
    wam_env_put(Env0, VarName, Val, H0, HTop0, Trail0,
                Env1, H1, HTop1, Trail1).

% --- hs_write(Expr) ---
wam_exec_instr(wam_instr(_, hs_write(Expr)),
               wam(H, HTop, Env, CPs, Trail, Rest, run),
               wam(H, HTop, Env, CPs, Trail, Rest, run)) :- !,
    wam_env_to_hs(Env, H, HsEnv),
    hs_eval(Expr, HsEnv, Val),
    hs_print_value(Val), nl.

% --- hs_nl ---
wam_exec_instr(wam_instr(_, hs_nl), State, State) :- !, nl.

% --- hs_ask(PromptExpr, VarName) ---
wam_exec_instr(wam_instr(_, hs_ask(Prompt, VarName)),
               wam(H0, HTop0, Env0, CPs, Trail0, Rest, run),
               wam(H1, HTop1, Env1, CPs, Trail1, Rest, run)) :- !,
    wam_env_to_hs(Env0, H0, HsEnv),
    hs_eval(Prompt, HsEnv, PromptStr),
    write(PromptStr), flush_output,
    read_line_to_string(user_input, Line),
    wam_env_put(Env0, VarName, Line, H0, HTop0, Trail0,
                Env1, H1, HTop1, Trail1).

% --- hs_if(Cond, ThenCode, ElseCode) ---
% Prepend the chosen branch to the remaining pending code.
wam_exec_instr(wam_instr(_, hs_if(Cond, ThenCode, ElseCode)),
               wam(H, HTop, Env, CPs, Trail, Rest, run),
               wam(H, HTop, Env, CPs, Trail, NewPending, run)) :- !,
    wam_env_to_hs(Env, H, HsEnv),
    (   hs_eval_cond(Cond, HsEnv)
    ->  Branch = ThenCode
    ;   Branch = ElseCode
    ),
    append(Branch, Rest, NewPending).

% --- hs_repeat(Var, FromExpr, ToExpr, BodyCode) ---
% Expand one iteration; queue the next via a fresh hs_repeat instruction.
wam_exec_instr(wam_instr(Line, hs_repeat(Var, FromExpr, ToExpr, BodyCode)),
               wam(H0, HTop0, Env0, CPs, Trail0, Rest, run),
               wam(H1, HTop1, Env1, CPs, Trail1, NewPending, run)) :- !,
    wam_env_to_hs(Env0, H0, HsEnv),
    hs_eval(FromExpr, HsEnv, From),
    hs_eval(ToExpr,   HsEnv, To),
    (   From > To
    ->  H1 = H0, HTop1 = HTop0, Env1 = Env0, Trail1 = Trail0,
        NewPending = Rest
    ;   Next is From + 1,
        wam_env_put(Env0, Var, From, H0, HTop0, Trail0,
                    Env1, H1, HTop1, Trail1),
        NextRepeat = wam_instr(Line, hs_repeat(Var, num(Next), ToExpr, BodyCode)),
        append(BodyCode, [NextRepeat | Rest], NewPending)
    ).

% --- hs_call(F, ArgExprs) ---
% Evaluate args in the HyperScript env and call the Prolog goal.
wam_exec_instr(wam_instr(_, hs_call(F, ArgExprs)),
               wam(H, HTop, Env, CPs, Trail, Rest, run),
               wam(H, HTop, Env, CPs, Trail, Rest, run)) :- !,
    wam_env_to_hs(Env, H, HsEnv),
    maplist(hs_eval_arg_wam(HsEnv), ArgExprs, Args),
    hs_prelude_call(F, Args).

hs_eval_arg_wam(Env, Expr, Val) :- hs_eval(Expr, Env, Val).

% ===========================================================================
% 9. Meta-interpreter for hs_query (uses Prolog native backtracking)
%
% The meta-interpreter uses a plain list env: [Name-PrologTerm, ...]
% Prolog variables in the env are automatically managed by Prolog's trail,
% so backtracking through choice points undoes bindings for free.
% ===========================================================================

%% expr_var_names(+Expr, -Names)
% Collect all var(Name) variable names that appear in an expression AST.
expr_var_names(var(N), [N]) :- !.
expr_var_names(T, Ns) :-
    compound(T), !,
    T =.. [_ | Args],
    maplist(expr_var_names, Args, NLists),
    flatten(NLists, Ns0),
    list_to_set(Ns0, Ns).
expr_var_names(_, []).

%% ensure_mi_vars(+Names, +Env0, -Env1)
% For each name in Names not already in Env0, add a fresh Prolog variable.
ensure_mi_vars([], Env, Env).
ensure_mi_vars([N | Ns], Env0, Env2) :-
    (   memberchk(N-_, Env0)
    ->  Env1 = Env0
    ;   Env1 = [N-_ | Env0]
    ),
    ensure_mi_vars(Ns, Env1, Env2).

%% mi_eval(+Expr, +Env0, -Env1, -Val)
% Evaluate an expression in the meta-interpreter context.
% Creates fresh Prolog variables for any unbound variable names first.
mi_eval(Expr, Env0, Env1, Val) :-
    expr_var_names(Expr, Names),
    ensure_mi_vars(Names, Env0, Env1),
    hs_eval(Expr, Env1, Val).

%% mi_eval_list(+Exprs, +Env0, -Env1, -Vals)
mi_eval_list([], Env, Env, []).
mi_eval_list([E | Es], Env0, Env2, [V | Vs]) :-
    mi_eval(E, Env0, Env1, V),
    mi_eval_list(Es, Env1, Env2, Vs).

%% mi_eval_cond(+Cond, +Env0, -Env1)
% Evaluate a condition using the meta-interpreter env.
mi_eval_cond(cond(Op, L, R), Env0, Env2) :-
    mi_eval(L, Env0, Env1, LV),
    mi_eval(R, Env1, Env2, RV),
    hs_apply_cond(Op, LV, RV).
mi_eval_cond(cond_not(C), Env, Env) :-
    \+ mi_eval_cond(C, Env, _).
mi_eval_cond(call(true,  []), Env, Env) :- !.
mi_eval_cond(call(fail,  []), _,   _) :- !, fail.
mi_eval_cond(call(false, []), _,   _) :- !, fail.
mi_eval_cond(call(F, ArgExprs), Env0, Env1) :-
    mi_eval_list(ArgExprs, Env0, Env1, Args),
    hs_prelude_call(F, Args).
mi_eval_cond(call(F, []), Env, Env) :-
    hs_prelude_call(F, []).

%% mi_env_set(+Name, +Val, +Env0, -Env1)
% Update or insert Name=Val in the meta-interpreter env.
mi_env_set(Name, Val, Env0, Env1) :-
    (   select(Name-_, Env0, Rest)
    ->  Env1 = [Name-Val | Rest]
    ;   Env1 = [Name-Val | Env0]
    ).

%% wam_meta_exec(+Pending, +Env0, -Env1)
% Execute WAM bytecode using Prolog's native backtracking.
wam_meta_exec([], Env, Env).
wam_meta_exec([wam_instr(_, proceed) | _], Env, Env) :- !.
wam_meta_exec([Instr | Rest], Env0, EnvOut) :-
    wam_mi_step(Instr, Rest, Env0, EnvOut).

%% wam_mi_step(+Instr, +Rest, +Env0, -Env1)
wam_mi_step(wam_instr(_, proceed), _, Env, Env) :- !.

wam_mi_step(wam_instr(_, fail), _, _, _) :- !, fail.

wam_mi_step(wam_instr(_, cut), Rest, Env0, EnvOut) :- !,
    wam_meta_exec(Rest, Env0, EnvOut).

% try_me_else: use Prolog's native ';' for choice points
wam_mi_step(wam_instr(_, try_me_else(AltPending)), Rest, Env0, EnvOut) :- !,
    (   wam_meta_exec(Rest, Env0, EnvOut)
    ;   wam_meta_exec(AltPending, Env0, EnvOut)
    ).

wam_mi_step(wam_instr(_, hs_put(Expr, VarName)), Rest, Env0, EnvOut) :- !,
    mi_eval(Expr, Env0, Env1, Val),
    mi_env_set(VarName, Val, Env1, Env2),
    wam_meta_exec(Rest, Env2, EnvOut).

wam_mi_step(wam_instr(_, hs_write(Expr)), Rest, Env0, EnvOut) :- !,
    mi_eval(Expr, Env0, Env1, Val),
    hs_print_value(Val), nl,
    wam_meta_exec(Rest, Env1, EnvOut).

wam_mi_step(wam_instr(_, hs_nl), Rest, Env, EnvOut) :- !,
    nl,
    wam_meta_exec(Rest, Env, EnvOut).

wam_mi_step(wam_instr(_, hs_ask(Prompt, VarName)), Rest, Env0, EnvOut) :- !,
    mi_eval(Prompt, Env0, Env1, PromptStr),
    write(PromptStr), flush_output,
    read_line_to_string(user_input, Line),
    mi_env_set(VarName, Line, Env1, Env2),
    wam_meta_exec(Rest, Env2, EnvOut).

wam_mi_step(wam_instr(_, hs_if(Cond, ThenCode, ElseCode)), Rest, Env0, EnvOut) :- !,
    (   mi_eval_cond(Cond, Env0, Env1)
    ->  Branch = ThenCode
    ;   Branch = ElseCode, Env1 = Env0
    ),
    append(Branch, Rest, NewPending),
    wam_meta_exec(NewPending, Env1, EnvOut).

wam_mi_step(wam_instr(Line, hs_repeat(Var, FromExpr, ToExpr, BodyCode)),
            Rest, Env0, EnvOut) :- !,
    mi_eval(FromExpr, Env0, Env1, From),
    mi_eval(ToExpr,   Env1, Env2, To),
    (   From > To
    ->  wam_meta_exec(Rest, Env2, EnvOut)
    ;   Next is From + 1,
        mi_env_set(Var, From, Env2, Env3),
        NextRepeat = wam_instr(Line, hs_repeat(Var, num(Next), ToExpr, BodyCode)),
        append(BodyCode, [NextRepeat | Rest], NewPending),
        wam_meta_exec(NewPending, Env3, EnvOut)
    ).

wam_mi_step(wam_instr(_, hs_call(F, ArgExprs)), Rest, Env0, EnvOut) :- !,
    mi_eval_list(ArgExprs, Env0, Env1, Args),
    hs_prelude_call(F, Args),
    wam_meta_exec(Rest, Env1, EnvOut).

% ===========================================================================
% 10. Top-level API
% ===========================================================================

%% hs_run_bc(+Bytecode, -Env)
% Run WAM bytecode via the step machine; return final HyperScript env.
hs_run_bc(Bytecode, Env) :-
    wam_initial_state(Bytecode, State0),
    wam_run_to_done(State0, FinalState),
    FinalState = wam(Heap, _, WamEnv, _, _, _, Status),
    (   Status == halt
    ->  wam_env_to_hs(WamEnv, Heap, Env)
    ;   Status == fail
    ->  Env = []
    ;   throw(hs_wam_error(Status))
    ).

wam_run_to_done(State, State) :-
    wam_state_done(State), !.
wam_run_to_done(State0, State2) :-
    hs_step(State0, State1),
    wam_run_to_done(State1, State2).

%% hs_query(+Source, -Solutions)
% Compile Source and collect all solutions via the meta-interpreter.
% Each solution is a list of Name-Value pairs.
hs_query(Source, Solutions) :-
    hs_query_env(Source, [], Solutions).

%% hs_query_env(+Source, +InitEnv, -Solutions)
% Like hs_query/2 but starts with InitEnv as the initial variable environment.
% Allows a REPL to carry bindings across successive queries.
hs_query_env(Source, InitEnv, Solutions) :-
    hs_tokenise(Source, Tokens),
    hs_parse(Tokens, Stmts),
    hs_compile_ast(Stmts, Bytecode),
    findall(Env, wam_meta_exec(Bytecode, InitEnv, Env), Solutions).

%% hs_trace(+Source)
% Compile Source and execute step-by-step with trace output to stdout.
hs_trace(Source) :-
    hs_compile(Source, Bytecode),
    wam_initial_state(Bytecode, State0),
    hs_trace_run(State0).

hs_trace_run(State) :-
    wam_state_done(State), !,
    State = wam(Heap, _, WamEnv, _, _, _, Status),
    wam_env_to_hs(WamEnv, Heap, HsEnv),
    format("[trace] ~w~n", [Status]),
    (   HsEnv \= []
    ->  format("[bindings] ~w~n", [HsEnv])
    ;   true
    ).
hs_trace_run(State0) :-
    State0 = wam(H, _, Env, _, _, [wam_instr(Line, Op) | _], run), !,
    wam_env_to_hs(Env, H, HsEnv),
    format("[line ~w] CALL  ~w~n", [Line, Op]),
    (   HsEnv \= []
    ->  format("[line ~w] ENV   ~w~n", [Line, HsEnv])
    ;   true
    ),
    hs_step(State0, State1),
    State1 = wam(H1, _, Env1, CPs1, _, _, Status1),
    wam_env_to_hs(Env1, H1, HsEnv1),
    (   Status1 == fail
    ->  format("[line ~w] FAIL~n", [Line])
    ;   length(CPs1, NCPs1),
        format("[line ~w] EXIT  env=~w  cps=~w~n",
               [Line, HsEnv1, NCPs1])
    ),
    hs_trace_run(State1).
hs_trace_run(State0) :-
    State0 = wam(_, _, _, _, _, [], run), !,
    hs_step(State0, State1),
    hs_trace_run(State1).

% ===========================================================================
% Stage 6: Line-aware tracing with full I/O
% ===========================================================================

%% hs_set_trace(+OnOrOff)
% Set the global trace flag (on or off).
% Query hs_trace_enabled/1 to read the current state; defaults to off when
% no fact exists (i.e. before the first hs_set_trace/1 call).
:- dynamic hs_trace_enabled/1.

hs_set_trace(OnOrOff) :-
    retractall(hs_trace_enabled(_)),
    assertz(hs_trace_enabled(OnOrOff)).

%% hs_trace_source(+Source)
% Compile Source and execute step-by-step with enhanced line-aware trace output.
hs_trace_source(Source) :-
    hs_compile(Source, Bytecode),
    wam_initial_state(Bytecode, State0),
    hs_trace_run_s6(State0, []).

%% hs_trace_file(+File)
% Load a .hspl file and trace its execution line by line.
hs_trace_file(File) :-
    read_file_to_string(File, Source, []),
    hs_trace_source(Source).

%% hs_trace_query(+Query)
% Compile and trace Query as a HyperScript/Prolog source string.
% Equivalent to hs_trace_source/1 but named for Prolog-query use.
hs_trace_query(Query) :-
    hs_trace_source(Query).

% ---------------------------------------------------------------------------
% WAM op → human-readable string
% ---------------------------------------------------------------------------

%% wam_op_str(+Op, -Str)
% Format a WAM instruction operand as a concise, human-readable string.
wam_op_str(hs_put(Expr, Var), S) :- !,
    format(atom(S), "put ~w into ~w", [Expr, Var]).
wam_op_str(hs_write(Expr), S) :- !,
    format(atom(S), "write ~w", [Expr]).
wam_op_str(hs_nl, "nl") :- !.
wam_op_str(hs_ask(Prompt, Var), S) :- !,
    format(atom(S), "ask ~w giving ~w", [Prompt, Var]).
wam_op_str(hs_if(Cond, _, _), S) :- !,
    format(atom(S), "if ~w", [Cond]).
wam_op_str(hs_repeat(Var, From, To, _), S) :- !,
    format(atom(S), "repeat ~w from ~w to ~w", [Var, From, To]).
wam_op_str(hs_call(F, Args), S) :- !,
    format(atom(S), "~w(~w)", [F, Args]).
wam_op_str(try_me_else(_), "try_me_else") :- !.
wam_op_str(proceed, "proceed") :- !.
wam_op_str(fail, "fail") :- !.
wam_op_str(cut, "cut") :- !.
wam_op_str(Op, S) :- format(atom(S), "~w", [Op]).

% ---------------------------------------------------------------------------
% Enhanced trace runner  (hs_trace_run_s6/2)
% ---------------------------------------------------------------------------

%% hs_trace_run_s6(+State, +PrevHsEnv)
% Step through the WAM State, emitting structured trace events:
%
%   [line N] CALL  <human-readable op>
%   [line N] IO write(<value>)           – for hs_write instructions
%   [line N] IO read(<var>)              – for hs_ask instructions
%   [line N] CP+  (count: N)             – choice-point created
%   [line N] CP-  (count: N)             – choice-point removed (backtrack)
%   [line N] REDO                        – re-entering after backtrack
%   [line N] EXIT <Name = Val | true>    – successful step, new bindings
%   [line N] FAIL                        – step failed
%   [trace]  halt | fail                 – final status
%   [bindings] Name = Val                – final variable bindings

hs_trace_run_s6(State, _PrevEnv) :-
    wam_state_done(State), !,
    State = wam(Heap, _, WamEnv, _, _, _, Status),
    format("[trace] ~w~n", [Status]),
    wam_env_to_hs(WamEnv, Heap, HsEnv),
    ( HsEnv \= [] ->
        forall(member(Name-Val, HsEnv),
               format("[bindings] ~w = ~w~n", [Name, Val]))
    ; true ).

hs_trace_run_s6(State0, _) :-
    State0 = wam(H0, _, Env0, CPs0, _, [Instr | _], run), !,
    Instr = wam_instr(Line, Op),
    wam_op_str(Op, Display),
    format("[line ~w] CALL ~w~n", [Line, Display]),
    % Announce choice-point creation for try_me_else
    length(CPs0, NCPs0),
    ( Op = try_me_else(_) ->
        NCPsNew is NCPs0 + 1,
        format("[line ~w] CP+ (count: ~w)~n", [Line, NCPsNew])
    ; true ),
    % Pre-announce I/O for write and ask instructions
    wam_env_to_hs(Env0, H0, HsEnv0),
    ( Op = hs_write(WriteExpr) ->
        ( catch(hs_eval(WriteExpr, HsEnv0, WriteVal),
                EvalErr,
                (WriteVal = '?',
                 format("[line ~w] ERROR evaluating write arg: ~w~n",
                        [Line, EvalErr])))
        -> format("[line ~w] IO write(~w)~n", [Line, WriteVal])
        ;  format("[line ~w] IO write(?)~n", [Line])
        )
    ; Op = hs_ask(_, ReadVar) ->
        format("[line ~w] IO read(~w)~n", [Line, ReadVar])
    ; true ),
    % Execute the WAM step
    hs_step(State0, State1),
    State1 = wam(H1, _, Env1, CPs1, _, _, Status1),
    % Detect choice-point removal (backtracking occurred)
    length(CPs1, NCPs1),
    ( NCPs1 < NCPs0 ->
        format("[line ~w] CP- (count: ~w)~n", [Line, NCPs1]),
        format("[line ~w] REDO~n", [Line])
    ; true ),
    % Show EXIT with new/changed bindings, or FAIL
    wam_env_to_hs(Env1, H1, HsEnv1),
    ( Status1 == fail ->
        format("[line ~w] FAIL~n", [Line])
    ;
        s6_new_bindings(HsEnv0, HsEnv1, NewBindings),
        ( NewBindings = [] ->
            format("[line ~w] EXIT true~n", [Line])
        ;
            forall(member(BName-BVal, NewBindings),
                   format("[line ~w] EXIT ~w = ~w~n", [Line, BName, BVal]))
        )
    ),
    hs_trace_run_s6(State1, HsEnv1).

hs_trace_run_s6(State0, PrevEnv) :-
    State0 = wam(_, _, _, _, _, [], run), !,
    hs_step(State0, State1),
    hs_trace_run_s6(State1, PrevEnv).

%% s6_new_bindings(+OldEnv, +NewEnv, -NewOrChangedBindings)
% Select bindings from NewEnv that are absent or changed in OldEnv.
s6_new_bindings(OldEnv, NewEnv, NewBindings) :-
    include(s6_binding_changed(OldEnv), NewEnv, NewBindings).

s6_binding_changed(OldEnv, Name-Val) :-
    \+ memberchk(Name-Val, OldEnv).
