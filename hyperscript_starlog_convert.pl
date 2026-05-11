%% hyperscript_starlog_convert.pl
%%
%% Stage 8 – Conversion to/from compressed Starlog.

:- module(hyperscript_starlog_convert, [
    hs_to_starlog/3,
    starlog_to_hs/3
]).

:- use_module(hyperscript_parser, [hs_tokenise/2, hs_parse/2]).
:- use_module(hyperscript_errors, [hs_conversion_error/3]).

%% hs_to_starlog(+HyperScriptSource, +Options, -StarlogSource)
hs_to_starlog(HyperScriptSource, Options, StarlogSource) :-
    catch(hs_to_starlog_impl(HyperScriptSource, Options, StarlogSource),
          E,
          ( hs_conversion_error(to_starlog, E, Err),
            throw(Err) )).

hs_to_starlog_impl(HyperScriptSource, Options, StarlogSource) :-
    hs_option(style, Options, nested, Style0),
    normalise_style(Style0, Style),
    hs_option(preserve_comments, Options, false, PreserveComments),
    hs_option(compressed, Options, true, _Compressed),
    hs_option(trace, Options, false, _Trace),
    hs_tokenise(HyperScriptSource, Tokens),
    hs_parse(Tokens, AST),
    maplist(hs_stmt_to_starlog_line(Style), AST, CodeLines),
    include(non_empty_string, CodeLines, CodeLines1),
    source_comment_lines(HyperScriptSource, CommentLines0),
    ( PreserveComments == true -> CommentLines = CommentLines0 ; CommentLines = [] ),
    append(CommentLines, CodeLines1, AllLines),
    atomic_list_concat(AllLines, "\n", StarlogSource).

%% starlog_to_hs(+StarlogSource, +Options, -HyperScriptSource)
starlog_to_hs(StarlogSource, Options, HyperScriptSource) :-
    catch(starlog_to_hs_impl(StarlogSource, Options, HyperScriptSource),
          E,
          ( hs_conversion_error(from_starlog, E, Err),
            throw(Err) )).

starlog_to_hs_impl(StarlogSource, Options, HyperScriptSource) :-
    hs_option(style, Options, nested, Style0),
    normalise_style(Style0, Style),
    hs_option(preserve_comments, Options, true, PreserveComments),
    hs_option(compressed, Options, true, _Compressed),
    hs_option(trace, Options, false, _Trace),
    split_string(StarlogSource, "\n", "", RawLines),
    maplist(string_trim, RawLines, Trimmed),
    maplist(starlog_line_to_hs_line(Style, PreserveComments), Trimmed, HsLines0),
    include(non_empty_string, HsLines0, HsLines),
    atomic_list_concat(HsLines, "\n", HyperScriptSource).

hs_option(Key, Options, Default, Value) :-
    Opt =.. [Key, Value0],
    ( memberchk(Opt, Options) -> Value = Value0 ; Value = Default ).

normalise_style(method_chain, method_chain) :- !.
normalise_style(compressed, method_chain) :- !.
normalise_style(nested, nested) :- !.
normalise_style(_, nested).

non_empty_string(S) :- string(S), S \= "".

string_trim(In, Out) :- normalize_space(string(Out), In).

source_comment_lines(Source, CommentLines) :-
    split_string(Source, "\n", "", Lines),
    findall(LineOut,
        ( member(Line, Lines),
          string_trim(Line, Trimmed),
          string_concat("%", _, Trimmed),
          LineOut = Trimmed
        ),
        CommentLines).

hs_stmt_to_starlog_line(method_chain, put(Expr, Var), Line) :- !,
    hs_expr_to_starlog_method(Expr, ExprText),
    format(string(Line), "starlog_call(~w is ~w).", [Var, ExprText]).
hs_stmt_to_starlog_line(nested, put(Expr, Var), Line) :- !,
    hs_put_expr_to_nested_line(Expr, Var, Line).
hs_stmt_to_starlog_line(_Style, write(Expr), Line) :- !,
    hs_expr_to_starlog_method(Expr, ExprText),
    format(string(Line), "write(~w).", [ExprText]).
hs_stmt_to_starlog_line(_Style, nl, "nl.") :- !.
hs_stmt_to_starlog_line(_Style, call(F, Args), Line) :- !,
    maplist(hs_expr_to_starlog_method, Args, ArgTexts),
    atomic_list_concat(ArgTexts, ",", ArgStr),
    format(string(Line), "~w(~w).", [F, ArgStr]).
hs_stmt_to_starlog_line(_Style, ask(Prompt, Var), Line) :- !,
    hs_expr_to_starlog_method(Prompt, PromptText),
    format(string(Line), "ask(~w,~w).", [PromptText, Var]).
hs_stmt_to_starlog_line(_, if(_, _, _), _) :-
    throw(unsupported_if_conversion).
hs_stmt_to_starlog_line(_, repeat_with(_, _, _, _), _) :-
    throw(unsupported_repeat_conversion).

hs_put_expr_to_nested_line(concat(A, B), Var, Line) :- !,
    hs_expr_to_starlog_method(A, AT),
    hs_expr_to_starlog_method(B, BT),
    format(string(Line), "string_concat(~w,~w,~w).", [AT, BT, Var]).
hs_put_expr_to_nested_line(method_chain(Input, atom(Method)), Var, Line) :- !,
    hs_expr_to_starlog_method(Input, InputT),
    format(string(Line), "~w(~w,~w).", [Method, InputT, Var]).
hs_put_expr_to_nested_line(method_chain(Input, call(Method, Args)), Var, Line) :- !,
    hs_expr_to_starlog_method(Input, InputT),
    maplist(hs_expr_to_starlog_method, Args, ArgTs),
    append([InputT], ArgTs, WithInput),
    append(WithInput, [Var], AllArgs),
    atomic_list_concat(AllArgs, ",", ArgStr),
    format(string(Line), "~w(~w).", [Method, ArgStr]).
hs_put_expr_to_nested_line(call(F, Args), Var, Line) :- !,
    maplist(hs_expr_to_starlog_method, Args, ArgTs),
    append(ArgTs, [Var], AllArgs),
    atomic_list_concat(AllArgs, ",", ArgStr),
    format(string(Line), "~w(~w).", [F, ArgStr]).
hs_put_expr_to_nested_line(Expr, Var, Line) :-
    hs_expr_to_starlog_method(Expr, ExprText),
    format(string(Line), "~w is ~w.", [Var, ExprText]).

hs_expr_to_starlog_method(num(N), T) :- !, format(string(T), "~w", [N]).
hs_expr_to_starlog_method(str(S), T) :- !, format(string(T), "~q", [S]).
hs_expr_to_starlog_method(atom(A), T) :- !, format(string(T), "~q", [A]).
hs_expr_to_starlog_method(var(V), T) :- !, format(string(T), "~w", [V]).
hs_expr_to_starlog_method(list(Elems), T) :- !,
    maplist(hs_expr_to_starlog_method, Elems, ElemTs),
    atomic_list_concat(ElemTs, ",", Inner),
    format(string(T), "[~w]", [Inner]).
hs_expr_to_starlog_method(list_tail(Elems, Tail), T) :- !,
    maplist(hs_expr_to_starlog_method, Elems, ElemTs),
    hs_expr_to_starlog_method(Tail, TailT),
    atomic_list_concat(ElemTs, ",", Head),
    format(string(T), "[~w|~w]", [Head, TailT]).
hs_expr_to_starlog_method(concat(E1, E2), T) :- !,
    hs_expr_to_starlog_method(E1, A),
    hs_expr_to_starlog_method(E2, B),
    format(string(T), "~w:~w", [A, B]).
hs_expr_to_starlog_method(method_chain(E, M), T) :- !,
    hs_expr_to_starlog_method(E, EText),
    hs_method_to_text(M, MText),
    format(string(T), "~w >> ~w", [EText, MText]).
hs_expr_to_starlog_method(arith(Op, A, B), T) :- !,
    hs_expr_to_starlog_method(A, AT),
    hs_expr_to_starlog_method(B, BT),
    format(string(T), "(~w ~w ~w)", [AT, Op, BT]).
hs_expr_to_starlog_method(neg(E), T) :- !,
    hs_expr_to_starlog_method(E, ET),
    format(string(T), "-(~w)", [ET]).
hs_expr_to_starlog_method(call(F, Args), T) :- !,
    maplist(hs_expr_to_starlog_method, Args, ArgTs),
    atomic_list_concat(ArgTs, ",", ArgStr),
    format(string(T), "~w(~w)", [F, ArgStr]).
hs_expr_to_starlog_method(Expr, T) :-
    format(string(T), "~q", [Expr]).

hs_method_to_text(atom(Name), T) :-
    format(string(T), "~w", [Name]).
hs_method_to_text(call(Name, Args), T) :-
    maplist(hs_expr_to_starlog_method, Args, ArgTs),
    atomic_list_concat(ArgTs, ",", ArgStr),
    format(string(T), "~w(~w)", [Name, ArgStr]).

starlog_line_to_hs_line(_Style, PreserveComments, Line, Out) :-
    ( Line = ""
    -> Out = ""
    ; string_concat("%", _, Line)
    -> ( PreserveComments == true -> Out = Line ; Out = "" )
    ; strip_trailing_dot(Line, Core),
      ( parse_starlog_method_line(Core, Out)
      -> true
      ; parse_starlog_nested_line(Core, Out)
      -> true
      ; throw(cannot_parse_starlog_line(Core))
      )
    ).

strip_trailing_dot(Line, Core) :-
    ( sub_string(Line, _, 1, 0, ".")
    -> sub_string(Line, 0, _, 1, Core)
    ; Core = Line
    ).

parse_starlog_method_line(Line, HsLine) :-
    string_concat("starlog_call(", Rest, Line),
    string_concat(Inner, ")", Rest),
    hs_tokenise(Inner, Tokens),
    phrase(starlog_assignment(Var, Expr), Tokens),
    hs_expr_to_hs_text(Expr, ExprText),
    format(string(HsLine), "put ~w into ~w", [ExprText, Var]).

starlog_assignment(Var, Expr) -->
    [var(Var), atom(is)],
    starlog_expr(Expr).

starlog_expr(E) --> starlog_concat(E).

starlog_concat(concat(A, B)) -->
    starlog_chain(A), [op(Op)], { member(Op, [':', '&', '•']) }, !, starlog_concat(B).
starlog_concat(E) --> starlog_chain(E).

starlog_chain(E) -->
    starlog_primary(E0),
    starlog_chain_rest(E0, E).

starlog_chain_rest(Acc, E) -->
    [op('>>')], starlog_method(M), !,
    { Acc1 = method_chain(Acc, M) },
    starlog_chain_rest(Acc1, E).
starlog_chain_rest(E, E) --> [].

starlog_method(call(F, Args)) -->
    [atom(F)], [punct('(')], starlog_arg_list(Args), [punct(')')], !.
starlog_method(atom(F)) --> [atom(F)].

starlog_primary(num(N)) --> [number(N)], !.
starlog_primary(str(S)) --> [string(S)], !.
starlog_primary(var(V)) --> [var(V)], !.
starlog_primary(call(F, Args)) -->
    [atom(F)], [punct('(')], starlog_arg_list(Args), [punct(')')], !.
starlog_primary(atom(A)) --> [atom(A)], !.
starlog_primary(list(Elems)) -->
    [punct('[')], starlog_list_contents(Elems), [punct(']')], !.
starlog_primary(E) -->
    [punct('(')], starlog_expr(E), [punct(')')], !.

starlog_list_contents([]) --> [].
starlog_list_contents([E|Es]) -->
    starlog_expr(E), starlog_list_rest(Es).

starlog_list_rest([]) --> [].
starlog_list_rest([E|Es]) --> [punct(',')], starlog_expr(E), starlog_list_rest(Es).

starlog_arg_list([]) --> [].
starlog_arg_list([A|As]) -->
    starlog_expr(A), starlog_arg_list_rest(As).

starlog_arg_list_rest([]) --> [].
starlog_arg_list_rest([A|As]) -->
    [punct(',')], starlog_expr(A), starlog_arg_list_rest(As).

parse_starlog_nested_line(Line, HsLine) :-
    atom_string(AtomLine0, Line),
    ( sub_atom(AtomLine0, _, 1, 0, '.')
    -> AtomLine = AtomLine0
    ; atom_concat(AtomLine0, '.', AtomLine)
    ),
    read_term_from_atom(AtomLine, Term, [variable_names(VarNames)]),
    term_to_hs_line(Term, VarNames, HsLine).

term_to_hs_line(write(Arg), VNs, Line) :- !,
    term_to_hs_expr_text(Arg, VNs, ArgText),
    format(string(Line), "write ~w", [ArgText]).
term_to_hs_line(nl, _VNs, "nl") :- !.
term_to_hs_line(string_concat(A, B, V), VNs, Line) :- !,
    term_to_hs_expr_text(A, VNs, AT),
    term_to_hs_expr_text(B, VNs, BT),
    term_to_hs_var_name(V, VNs, VText),
    format(string(Line), "put ~w & ~w into ~w", [AT, BT, VText]).
term_to_hs_line(append(A, B, V), VNs, Line) :- !,
    term_to_hs_expr_text(A, VNs, AT),
    term_to_hs_expr_text(B, VNs, BT),
    term_to_hs_var_name(V, VNs, VText),
    format(string(Line), "put ~w & ~w into ~w", [AT, BT, VText]).
term_to_hs_line(atom_concat(A, B, V), VNs, Line) :- !,
    term_to_hs_expr_text(A, VNs, AT),
    term_to_hs_expr_text(B, VNs, BT),
    term_to_hs_var_name(V, VNs, VText),
    format(string(Line), "put ~w & ~w into ~w", [AT, BT, VText]).
term_to_hs_line(Term, VNs, Line) :-
    compound(Term), !,
    Term =.. [F | Args],
    ( append(InArgs, [OutArg], Args),
      term_is_var(OutArg)
    -> maplist(term_to_hs_expr_text_(VNs), InArgs, InTexts),
       atomic_list_concat(InTexts, ",", ArgStr),
       term_to_hs_var_name(OutArg, VNs, OutName),
       format(string(Line), "put ~w(~w) into ~w", [F, ArgStr, OutName])
    ; maplist(term_to_hs_expr_text_(VNs), Args, ArgTexts),
      atomic_list_concat(ArgTexts, ",", ArgStr),
      format(string(Line), "~w(~w)", [F, ArgStr])
    ).
term_to_hs_line(Term, _VNs, Line) :-
    format(string(Line), "write ~q", [Term]).

term_to_hs_expr_text_(VNs, Term, Text) :-
    term_to_hs_expr_text(Term, VNs, Text).

term_to_hs_expr_text(Term, VNs, Text) :-
    ( var(Term)
    -> term_to_hs_var_name(Term, VNs, Text)
    ; number(Term)
    -> format(string(Text), "~w", [Term])
    ; string(Term)
    -> format(string(Text), "~q", [Term])
    ; atom(Term), Term \= []
    -> format(string(Text), "~q", [Term])
    ; Term == []
    -> Text = "[]"
    ; is_list(Term)
    -> maplist(term_to_hs_expr_text_(VNs), Term, ElemTexts),
       atomic_list_concat(ElemTexts, ",", Inner),
       format(string(Text), "[~w]", [Inner])
    ; compound(Term),
      Term =.. [':', A, B]
    -> term_to_hs_expr_text(A, VNs, AT),
       term_to_hs_expr_text(B, VNs, BT),
       format(string(Text), "~w & ~w", [AT, BT])
    ; compound(Term),
      Term =.. ['&', A, B]
    -> term_to_hs_expr_text(A, VNs, AT),
       term_to_hs_expr_text(B, VNs, BT),
       format(string(Text), "~w & ~w", [AT, BT])
    ; compound(Term),
      Term =.. ['•', A, B]
    -> term_to_hs_expr_text(A, VNs, AT),
       term_to_hs_expr_text(B, VNs, BT),
       format(string(Text), "~w & ~w", [AT, BT])
    ; compound(Term),
      Term =.. ['>>', A, B]
    -> term_to_hs_expr_text(A, VNs, AT),
       term_to_hs_expr_text(B, VNs, BT),
       format(string(Text), "~w >> ~w", [AT, BT])
    ; compound(Term)
    -> Term =.. [F | Args],
       maplist(term_to_hs_expr_text_(VNs), Args, ArgTexts),
       atomic_list_concat(ArgTexts, ",", ArgStr),
       format(string(Text), "~w(~w)", [F, ArgStr])
    ; format(string(Text), "~q", [Term])
    ).

term_is_var(Term) :- var(Term).

term_to_hs_var_name(Term, VNs, Name) :-
    ( var(Term),
      memberchk(NameAtom=Term, VNs)
    -> atom_string(NameAtom, Name)
    ; var(Term)
    -> Name = "_"
    ; atom(Term)
    -> atom_string(Term, Name)
    ; term_to_hs_expr_text(Term, VNs, Name)
    ).

hs_expr_to_hs_text(num(N), T) :- !, format(string(T), "~w", [N]).
hs_expr_to_hs_text(str(S), T) :- !, format(string(T), "~q", [S]).
hs_expr_to_hs_text(atom(A), T) :- !, format(string(T), "~q", [A]).
hs_expr_to_hs_text(var(V), T) :- !, format(string(T), "~w", [V]).
hs_expr_to_hs_text(list(Elems), T) :- !,
    maplist(hs_expr_to_hs_text, Elems, ElemTs),
    atomic_list_concat(ElemTs, ",", Inner),
    format(string(T), "[~w]", [Inner]).
hs_expr_to_hs_text(concat(A, B), T) :- !,
    hs_expr_to_hs_text(A, AT),
    hs_expr_to_hs_text(B, BT),
    format(string(T), "~w & ~w", [AT, BT]).
hs_expr_to_hs_text(method_chain(A, M), T) :- !,
    hs_expr_to_hs_text(A, AT),
    hs_method_to_hs_text(M, MT),
    format(string(T), "~w >> ~w", [AT, MT]).
hs_expr_to_hs_text(call(F, Args), T) :- !,
    maplist(hs_expr_to_hs_text, Args, ArgTs),
    atomic_list_concat(ArgTs, ",", ArgStr),
    format(string(T), "~w(~w)", [F, ArgStr]).
hs_expr_to_hs_text(arith(Op, A, B), T) :- !,
    hs_expr_to_hs_text(A, AT),
    hs_expr_to_hs_text(B, BT),
    format(string(T), "(~w ~w ~w)", [AT, Op, BT]).
hs_expr_to_hs_text(neg(E), T) :- !,
    hs_expr_to_hs_text(E, ET),
    format(string(T), "-(~w)", [ET]).
hs_expr_to_hs_text(E, T) :-
    format(string(T), "~q", [E]).

hs_method_to_hs_text(atom(F), T) :-
    format(string(T), "~w", [F]).
hs_method_to_hs_text(call(F, Args), T) :-
    maplist(hs_expr_to_hs_text, Args, ArgTs),
    atomic_list_concat(ArgTs, ",", ArgStr),
    format(string(T), "~w(~w)", [F, ArgStr]).
