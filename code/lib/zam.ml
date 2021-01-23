type inst_t =
    | Ldi of int
    | Ldb of bool
    | Lds of string
    | Access of int
    | Closure of code_t
    | Let
    | EndLet
    | Test of code_t * code_t
    | Add
    | Sub
    | Mul
    | Div
    | Mod
    | Gret
    | Less
    | And
    | Or
    | Eq
    | Neq
    | App
    | TailApp
    | PushMark
    | Grab
    | Return
[@@deriving show]
and code_t = inst_t list
[@@deriving show]

type val_t =
    | Int of int
    | Bool of bool
    | Str of string
    | ClosVal of code_t * env_t
    | Eps
[@@deriving show]
and env_t = val_t list
and stack_t = val_t list

type zam_t ={
    code: code_t;
    env: env_t;
    astack: stack_t;
    rstack: stack_t;
}
[@@deriving show]

let rec exec zam =
    let bin_i_i op = match zam.astack with
        | Int lhr :: Int rhr :: astack ->
            exec { zam with code = List.tl zam.code; astack = Int (op lhr rhr) :: astack }
        | _ -> failwith "cannot execute op: int -> int -> int"
    in
    let bin_i_b op = match zam.astack with
        | Int lhr :: Int rhr :: astack ->
            exec { zam with code = List.tl zam.code;  astack = Bool (op lhr rhr) :: astack }
        | _ -> failwith "cannot execute op: int -> int -> bool"
    in
    let bin_b_b op = match zam.astack with
        | Bool lhr :: Bool rhr :: astack ->
            exec { zam with code = List.tl zam.code;  astack = Bool (op lhr rhr) :: astack }
        | _ -> failwith "cannot execute op: bool -> bool -> bool"
    in
    match zam.code with
    | [] -> begin match zam with
        | { code = []; rstack = []; astack = [v]; env = [] } -> v
        | _ -> failwith "invalid state"
    end
    | Ldi i :: code -> exec { zam with code = code; astack = Int i :: zam.astack }
    | Ldb b :: code -> exec { zam with code = code; astack = Bool b :: zam.astack }
    | Lds s :: code -> exec { zam with code = code; astack = Str s :: zam.astack }
    | Access addr :: code -> exec { zam with code = code; astack = (List.nth zam.env addr) :: zam.astack }
    | EndLet :: code -> exec { zam with code = code; env = List.tl zam.env }
    | Let :: code -> exec { zam with code = code; env = (List.hd zam.astack) :: zam.env; astack = List.tl zam.astack }
    | Closure code' :: code ->
        exec { zam with code = code; astack = ClosVal (code', zam.env) :: zam.astack; }
    | App :: code -> begin match zam.astack with
        | ClosVal (code', env') as c :: astack ->
            exec { code = code'; astack = astack; env = c :: env'; rstack = ClosVal(code, zam.env) :: zam.rstack }
        | _ -> failwith "cannot execute app"
    end
    | TailApp :: _ -> begin match zam.astack with
        | ClosVal (code', env') as c :: astack ->
            exec { zam with code = code'; astack = astack; env = c :: env' }
        | _ -> failwith "cannot execute app"
    end
    | Grab :: code -> begin match (zam.astack, zam.rstack) with
        | (Eps :: astack, ClosVal(code', env') :: rstack) ->
            exec { code = code'; env = env'; astack = ClosVal(code, zam.env) :: astack; rstack = rstack }
        | (v :: astack, _) ->
            exec { zam with code = code; astack = astack; env = v :: ClosVal(code, zam.env) :: zam.env } | _ -> failwith "cannot execute grab"
    end
    | Return :: _ -> begin match (zam.astack, zam.rstack) with
        | (v :: Eps :: astack, ClosVal(code', env') :: rstack) ->
            exec { code = code'; env = env'; astack = v :: astack; rstack = rstack }
        | (ClosVal(code', env') as c :: v :: astack, _) ->
            exec { zam with code = code'; env = v :: c :: env'; astack = astack }
        | (astack, rstack) -> failwith @@ Printf.sprintf "cannot execute return %s, %s" (show_stack_t astack) (show_stack_t rstack)
    end
    | PushMark :: code -> exec { zam with code = code; astack = Eps :: zam.astack }
    | Test (c1, c2) :: code -> begin match List.hd zam.astack with
        | Bool true -> exec { zam with code = c1 @ code; astack = List.tl zam.astack }
        | Bool false -> exec { zam with code = c2 @ code; astack = List.tl zam.astack }
        | _ -> failwith "test needs boolean value as condition"
    end
    | And :: _ -> bin_b_b ( && )
    | Or :: _ -> bin_b_b ( || )
    | Add :: _ -> bin_i_i ( + )
    | Sub :: _ -> bin_i_i ( - )
    | Mul :: _ -> bin_i_i ( * )
    | Div :: _ -> bin_i_i ( / )
    | Mod :: _ -> bin_i_i ( mod )
    | Gret :: _ -> bin_i_b ( > )
    | Less :: _ -> bin_i_b ( < )
    | Eq :: code -> begin match zam.astack with
        | Bool lhr :: Bool rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | Int lhr :: Int rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | Str lhr :: Str rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | _ -> failwith "cannot execute op: bool -> bool -> bool"
    end
    | Neq :: code -> begin match zam.astack with
        | Bool lhr :: Bool rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | Int lhr :: Int rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | Str lhr :: Str rhr :: astack ->
            exec { zam with code = code;  astack = Bool (lhr = rhr) :: astack }
        | _ -> failwith "cannot execute op: bool -> bool -> bool"
    end
