[@@@coverage off]

type t =
  | Var of Symbol.t
  | Const of Const.t
  | Call of Symbol.t * t list
[@@deriving eq, show]

type category =
  | Global
  | Local
  | Trivial
[@@deriving eq, show]

let var x = Var (Symbol.of_string x)

let int x = Const (Const.Int x)

let string s = Const (Const.String s)

let call (op, args) = Call (Symbol.of_string op, args)

let var_list symbols = List.map (fun x -> Var x) symbols

let of_bool = function
  | true -> Call (Symbol.of_string "T", [])
  | false -> Call (Symbol.of_string "F", [])
;;

let panic fmt =
    Printf.ksprintf (fun s -> Call (Symbol.of_string "Panic", [ string s ])) fmt
;;

let rec subst ~(env : t Symbol_map.t) = function
  | Var x as default -> Option.value ~default (Symbol_map.find_opt x env)
  | Const const -> Const const
  | Call (op, args) -> Call (op, List.map (subst ~env) args)
;;

let subst_params ~params ~args t = subst ~env:(Symbol_map.setup2 (params, args)) t

[@@@coverage on]

let match_against (t1, t2) : t Symbol_map.t option =
    let exception Fail in
    let subst = ref Symbol_map.empty in
    let rec go (t1, t2) =
        match t1 with
        | Var x ->
          (match Symbol_map.find_opt x !subst with
           | Some x_subst -> if not (equal x_subst t2) then raise_notrace Fail
           | None -> subst := Symbol_map.add x t2 !subst)
        | Const const -> if not (equal (Const const) t2) then raise_notrace Fail
        | Call (op, args) ->
          (match t2 with
           | Call (op', args') when op = op' ->
             List.iter2 (fun t1 t2 -> go (t1, t2)) args args'
           | _ -> raise_notrace Fail)
    in
    try
      go (t1, t2);
      Some !subst
    with
    | Fail -> None
;;

[@@@coverage off]

let is_var = function
  | Var _ -> true
  | _ -> false
;;

let is_const = function
  | Const _ -> true
  | _ -> false
;;

let rec is_value = function
  | Var _ | Const _ -> true
  | Call (op, args) ->
    (match Symbol.kind op with
     | `CCall -> op <> Symbol.of_string "Panic"
     | `FCall -> is_neutral (Call (op, args))
     | `GCall -> false)

and is_neutral = function
  | Var _ -> true
  | Const _ -> false
  | Call (op, [ t ]) when Symbol.is_op1 op -> is_neutral t
  | Call (op, [ t1; t2 ]) when Symbol.is_op2 op ->
    (is_neutral t1 && is_value t2) || (is_value t1 && is_neutral t2)
  | Call (_op, _args) -> false
;;

[@@@coverage on]

let classify : t -> category =
    let rec go = function
      | Var _ | Const _ -> Trivial
      | Call (op, args) -> go_call (Symbol.kind op, args)
    and go_call = function
      | `CCall, _args -> Trivial
      | `GCall, Var _x :: _args -> Global
      | (`FCall | `GCall), args -> go_args args
    and go_args = function
      | [] -> Local
      | t :: rest ->
        (match go t with
         | Global -> Global
         | Local | Trivial -> go_args rest)
    in
    go
;;

[@@@coverage off]

let rec to_string = function
  | Var x -> Symbol.to_string x
  | Const const -> Const.to_string const
  | Call (op, args) ->
    Printf.sprintf
      "%s(%s)"
      (Symbol.to_string op)
      (String.concat ", " (List.map to_string args))
;;

let verbatim t = "`" ^ to_string t ^ "`"
