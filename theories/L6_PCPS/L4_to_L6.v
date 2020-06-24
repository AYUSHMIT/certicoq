(* Conversion from L4.expression to L6.cps *)

Require Import Coq.ZArith.ZArith Coq.Lists.List Coq.Strings.String.
Require Import Program Arith.
Require Import ExtLib.Data.String.
Require Import Common.AstCommon.
Require Import Znumtheory.
Require Import Bool.
(* ask about this import *)
Require compcert.lib.Maps.
Require Recdef.
Import Nnat.

Require Import L4.expression L4.exp_eval.
Require Import Coq.Relations.Relation_Definitions.
Require Import cps.
Require Import cps_show.
Require Import eval.
Require Import ctx.
Require Import logical_relations.
Require Import alpha_conv.

Require Import ExtLib.Data.Monads.OptionMonad.
Require Import ExtLib.Structures.Monads.

Import Monad.MonadNotation.
Open Scope monad_scope.

Definition func_tag := 5%positive. (* Regular function (lam) in cps *)
Definition kon_tag := 6%positive. (* continuation in cps *)

Definition default_tag := 7%positive.
Definition default_itag := 8%positive.

Definition conId_map:= list (dcon * ctor_tag).

Theorem conId_dec: forall x y:dcon, {x = y} + {x <> y}.
Proof.
  intros. destruct x,y.
  assert (H:= AstCommon.inductive_dec i i0).
  destruct H.
  - destruct (classes.eq_dec n n0).
    + subst. left. auto.
    + right. intro. apply n1. inversion H. auto.
  - right; intro; apply n1. inversion H; auto.
Defined.

Fixpoint dcon_to_info (a:dcon) (sig:conId_map) :=
  match sig with
  | nil => default_tag
  | ((cId, inf)::sig') => match conId_dec a cId with
                          | left _ => inf
                          | right _ => dcon_to_info a sig'
                          end
  end.

Definition dcon_to_tag (a:dcon) (sig:conId_map) :=
  dcon_to_info a sig.


Definition name_env := M.t BasicAst.name.
Definition n_empty:name_env := M.empty _.

Definition t_info:Type := fun_tag.
Definition t_map := M.t t_info.
Definition t_empty:t_map := M.empty _.

(* get the fun_tag of a variable, func_tag if not found *)
Fixpoint get_f (n:var) (sig:t_map): fun_tag :=
  match M.get n sig with
  | None => func_tag
  | Some v => v
  end.


Definition s_map := M.t var.
Definition s_empty := M.empty var.


Definition constr_env:Type := conId_map.

Definition ienv := list (string * AstCommon.itypPack).


Inductive symgen := SG : (var * name_env) -> symgen.

Definition gensym : symgen -> name -> (var * symgen) :=
  fun s n => match s with
           | SG (i, nenv) =>
             let env' := M.set i n nenv in
             (i, SG (Pos.succ i, env'))
             end.

Fixpoint gensym_n' (i : var) (env : name_env) (nlst : list name) :=
  match nlst with
  | nil => (nil, env, i)
  | cons n nlst' =>
    let env' := M.set i n env in
    let '(vlst, env'', next) := gensym_n' (Pos.succ i) env' nlst' in
    (i::vlst, env'', next)
  end.

Definition gensym_n : symgen -> list name -> (list var * symgen) :=
  fun s nlst => match s with
                | SG (i, nenv) =>
                  let '(ilst, nenv', next) := gensym_n' i nenv nlst in
                  (ilst, SG (next, nenv'))
                end.

Fixpoint gensym_n_nAnon' (i : var) (env : name_env )
         (n : nat) : (list var * name_env * var) :=
  match n with
  | O => (nil, env, i)
  | S n' =>
    let env' := M.set i nAnon env in
    let '(vlst, env'', next_var) := gensym_n_nAnon' (Pos.succ i) env' n' in
    (i::vlst, env'', next_var)
  end.

Definition gensym_n_nAnon (s : symgen) (n : nat) : (list var * symgen) :=
  match s with
    SG (i, nenv) =>
    let '(ilist, nenv', next_var) := gensym_n_nAnon' i nenv n in
    (ilist, SG (next_var, nenv'))
  end.

Fixpoint gen_nlst (n : nat) : list name :=
  match n with
  | O => nil
  | S n' => (nNamed "f"%string) :: (gen_nlst n')
  end.

(* helper function for building name_env *)
(*
Definition set_n (x:var) (n:BasicAst.name) (tgm:conv_env) : conv_env :=
  let '(t1,t2,t3) := tgm in
  (t1, t2, M.set x n t3).

Fixpoint add_names lnames vars tgm : conv_env :=
  match lnames, vars with
  | nil, nil => tgm
  | l::lnames', v::vars' =>
    let tgm := set_n v l tgm in
    add_names lnames' vars' tgm
  | _, _ => tgm
  end.
*)

(* returns list of numbers [n, n+m[  and the positive n+m (next available pos) *)
Fixpoint fromN (n:positive) (m:nat) : list positive * positive :=
  match m with
  | O => (nil, n)
  | S m' =>
    let (l, nm ) := (fromN (n+1) (m')) in
    (n::l, nm)
  end.


(* Bind m projections (starting from the (p+1)th) of var r to
   variables [n, n+m[, returns the generated context and n+m *)
Fixpoint ctx_bind_proj (tg:ctor_tag) (r:positive) (m:nat) (n:var) (p:nat)
  : (exp_ctx * var) :=
    match m with
      | O => (Hole_c, n)
      | S m' =>
        let (ctx_p', n') := ctx_bind_proj tg r m' n p in
        (Eproj_c  n' tg (N.of_nat (m'+p)) r ctx_p', Pos.succ n')
    end.

(* returns length of given expression.efnlst *)
Fixpoint efnlst_names (vs:efnlst) : nat * list name :=
  match vs with
    | eflnil => (O, nil)
    | eflcons n e fds' =>
      let (i, l) := efnlst_names fds' in
      ((S i), n::l)
  end.

(* definition of nth for the purposes of the cps_cvt function *)
Definition nth := nth_default (1%positive).


(** process a list of constructors from inductive type ind with ind_tag niT.
    - update the ctor_env with a mapping from the current ctor_tag to the cTypInfo
    - update the conId_map with a pair relating the nCon'th constructor of
      ind to the ctor_tag of the current constructor
   *)
Fixpoint convert_cnstrs (tyname:string) (cct:list ctor_tag) (itC:list AstCommon.Cnstr)
         (ind:BasicAst.inductive) (nCon:N) (unboxed : N) (boxed : N)
         (niT:ind_tag) (ce:ctor_env) (dcm:conId_map) :=
    match (cct, itC) with
      | (cn::cct', cst::icT') =>
        let (cname, ccn) := cst in
        let is_unboxed := Nat.eqb ccn 0 in
        let info := {| ctor_name := BasicAst.nNamed cname
                     ; ctor_ind_name := BasicAst.nNamed tyname
                     ; ctor_ind_tag := niT
                     ; ctor_arity := N.of_nat ccn
                     ; ctor_ordinal := if is_unboxed then unboxed else boxed
                     |} in
        convert_cnstrs tyname cct' icT' ind (nCon+1)%N
                       (if is_unboxed then unboxed + 1 else unboxed)
                       (if is_unboxed then boxed else boxed + 1)
                       niT
                       (M.set cn info ce)
                       (((ind,nCon), cn)::dcm (** Remove this now that params are always 0? *))
      | (_, _) => (ce, dcm)
    end.


(** For each inductive type defined in the mutually recursive bundle,
    - use tag niT for this inductive datatype
    - reserve constructor tags for each constructors of the type
    - process each of the constructor, indicating they are the ith constructor
      of the nth type of idBundle
    np: number of type parameters for this bundle
   *)
Fixpoint convert_typack typ (idBundle:string) (n:nat)
         (ice : (ind_env * ctor_env*  ctor_tag * ind_tag * conId_map))
  : (ind_env * ctor_env * ctor_tag * ind_tag * conId_map) :=
    let '(ie, ce, ncT, niT, dcm) := ice in
    match typ with
    | nil => ice
      (* let cct := (ncT::nil) in
      let ncT' := Pos.succ ncT in
      let itN := "Unit"%string in
      let itC := ((mkCnstr "prf"%string 0%nat) :: nil) in
      let (ce', dcm') :=
          convert_cnstrs itN cct itC (BasicAst.mkInd idBundle n) 0 niT ce dcm
      in
      let ityi := ((ncT, N.of_nat 0%nat)::nil) in
      (M.set niT ityi ie, ce', ncT', (Pos.succ niT), dcm') *)
    | (AstCommon.mkItyp itN itC ) ::typ' =>
      let (cct, ncT') := fromN ncT (List.length itC) in
      let (ce', dcm') :=
          convert_cnstrs itN cct itC (BasicAst.mkInd idBundle n) 0 0 0 niT ce dcm
      in
      let ityi :=
          combine cct (map (fun (c:AstCommon.Cnstr) =>
                              let (_, n) := c in N.of_nat n) itC)
      in
      convert_typack typ' idBundle (n+1)
                     (M.set niT ityi ie, ce', ncT', (Pos.succ niT) , dcm')
    end.


Fixpoint convert_env' (g:ienv) (ice:ind_env * ctor_env * ctor_tag * ind_tag * conId_map)
  : (ind_env * ctor_env * ctor_tag * ind_tag * conId_map) :=
  let '(ie, ce, ncT, niT, dcm) := ice in
  match g with
  | nil => ice
  | (id, ty)::g' =>
    (* id is name of mutual pack ty is mutual pack *)
    (* constructors are indexed with : name (string) of the mutual pack
       with which projection of the ty, and indice of the constructor *)
    convert_env' g' (convert_typack ty id 0 (ie, ce, ncT, niT, dcm))
  end.


 (** As we process the L4 inductive environment (ienv), we build:
    - an L6 inductive environment (ind_env) mapping tags (ind_tag) to constructors

      and their arities
      - an L6 constructor environment (ctor_env) mapping tags (ctor_tag) to
      information about the constructors
      - a map (conId_map) from L4 tags (conId) to L6 constructor tags (ctor_tag)
      convert_env' is called with the next available constructor tag and the
      next available inductive datatype tag, and inductive and constructor
      environment containing only the default "box" constructor/type
   *)
Definition convert_env (g:ienv): (ind_env * ctor_env*  ctor_tag * ind_tag * conId_map) :=
  let default_ind_env := M.set default_itag (cons (default_tag, 0%N) nil) (M.empty ind_ty_info) in
  let info := {| ctor_name := BasicAst.nAnon
                ; ctor_ind_name := BasicAst.nAnon
                ; ctor_ind_tag := default_itag
                ; ctor_arity := 0%N
                ; ctor_ordinal := 0%N
                |} in
  let default_ctor_env := M.set default_tag info (M.empty ctor_ty_info) in
  convert_env' g (default_ind_env, default_ctor_env, (Pos.succ default_tag:ctor_tag), (Pos.succ default_itag:ind_tag), nil).


(* vx is list of variables to which exps are bound in cvt_triples *)
Fixpoint cps_exps (ts : list (cps.exp * var * var)) (vx : list var) (k : var)
  : option (cps.exp) :=
  match ts with
  | nil => ret (cps.Eapp k kon_tag vx)
  | t::ts' =>
    let '(e1, k1, x1) := t in
    r <- cps_exps ts' vx k;;
      let e_exp := r in
      ret (cps.Efun
             (Fcons k1 kon_tag (x1::nil) e_exp Fnil)
             e1)
  end.

(* returns cps exp, var and next fresh var *)
Fixpoint cps_cvt (e : expression.exp) (vn : list var) (k : var) (next : symgen)
         (tgm : constr_env) : option (cps.exp * symgen) :=
  match e with
  | Var_e x =>
    let v := (nth vn (N.to_nat x)) in
    ret (cps.Eapp k kon_tag (v::nil), next)

  | App_e e1 e2 =>
    let (k1, next) := gensym next (nNamed "k1"%string) in
    let (x1, next) := gensym next (nNamed "x1"%string) in
    r1 <- cps_cvt e1 vn k1 (next) tgm;;
       let '(e1', next) := r1 : (cps.exp * symgen) in
       let (k2, next) := gensym next (nNamed "k2"%string) in
       let (x2, next) := gensym next (nNamed "x2"%string) in
       r2 <- cps_cvt e2 vn k2 (next) tgm;;
          let '(e2', next) := r2 : (cps.exp * symgen) in
          ret (cps.Efun
                 (Fcons k1 kon_tag (x1::nil)
                        (cps.Efun
                           (Fcons k2 kon_tag (x2::nil)
                                  (cps.Eapp x1 func_tag (x2::k::nil)) Fnil)
                           e2') Fnil)
                 e1', next)

  | Lam_e n e1 =>
    let (k1, next) := gensym next (nNamed "k_lam"%string) in
    let (x1, next) := gensym next (nNamed "x_lam"%string) in
    let (f, next) := gensym next n in
    (* let tgm := set_n f n tgm in *)
    r <- cps_cvt e1 (x1::vn) k1 (next) tgm;;
      let '(e1', next) := r : (cps.exp * symgen) in
      ret ((cps.Efun
              (Fcons f func_tag (x1::k1::nil) e1' Fnil)
              (cps.Eapp k kon_tag (f::nil))), next)

  | Let_e n e1 e2 =>
    (* let e' = L4.App_e (L4.Lam_e n e1) e2 in
    cps_cvt e' vn k next *)
    let (x, next) := gensym next n in
    let (k1, next) := gensym next (nNamed "k"%string) in
    r2 <- cps_cvt e2 (x::vn) k (next) tgm;;
       let '(e2', next) := r2 : (cps.exp * symgen) in
       r1 <- cps_cvt e1 vn k1 next tgm;;
          let '(e1', next) := r1 : (cps.exp * symgen) in
          (* let tgm := set_n x n tgm in *)
          ret (cps.Efun
                 (Fcons k1 kon_tag (x::nil) e2' Fnil)
                 e1', next)

  | Con_e dci es =>
    let c_tag := dcon_to_tag dci tgm in
    let (k', next) := gensym next (nNamed "k'"%string) in
    let (x', next) := gensym next (nNamed "x'"%string) in
    r1 <- cvt_triples_exps es vn next tgm;;
       let '(cvt_ts, next) := r1 in
       let vx := List.map
                   (fun x => let '(_, _, v) := x : (cps.exp * var * var) in v)
                   cvt_ts
       in
       r2 <- cps_exps cvt_ts vx k';;
          let e' := r2 in
          ret (cps.Efun
                 (Fcons k' kon_tag vx
                        (Econstr x' c_tag vx
                                 (Eapp k kon_tag (x'::nil))) Fnil)
                 e', next)

  | Fix_e fnlst i =>
    let (fnlst_length, names_lst) := efnlst_names fnlst in
    let (nlst, next) := gensym_n next names_lst in
    r <- cps_cvt_efnlst fnlst (nlst ++ vn) nlst next tgm;;
      let '(fdefs, next) := r : (fundefs * symgen) in
      let i' := (nth nlst (N.to_nat i)) in
      ret (cps.Efun fdefs
                    (cps.Eapp k kon_tag (i'::nil)),
           next)

  | Match_e e1 n bl =>
    let (k1, next) := gensym next (nNamed "k1"%string) in
    let (x1, next) := gensym next (nNamed "x1"%string) in
    r1 <- cps_cvt e1 vn k1 next tgm;;
       let '(e1', next) := r1 in
       r2 <- cps_cvt_branches bl vn k x1 next tgm;;
          let '(cbl, next) := r2 : (list (ctor_tag * exp) * symgen) in
          ret (cps.Efun
                 (Fcons k1 kon_tag (x1::nil)
                        (Ecase x1 cbl) Fnil)
                 e1', next)

  | Prf_e =>
    let (x, next) := gensym next (nNamed ""%string) in
    ret (cps.Econstr x default_tag nil (cps.Eapp k kon_tag (x::nil)), next)
  end

with cvt_triples_exps (es : expression.exps) (vn : list var) (next : symgen)
                      (tgm : constr_env)
     : option ((list (cps.exp * var * var)) * symgen) :=
       match es with
       | enil => ret (nil, next)
       | econs e es' =>
         let (k, next) := gensym next (nNamed ""%string) in
         let (x, next) := gensym next (nNamed ""%string) in
         r1 <- cps_cvt e vn k next tgm;;
            let '(e', next) := r1 in
            r2 <- cvt_triples_exps es' vn next tgm;;
               let '(cvt_ts', next) :=
                   r2 : (list (cps.exp * var * var)) * symgen in
               ret ((e', k, x) :: cvt_ts', next)
       end

(* nlst must be of the same length as fdefs *)
with cps_cvt_efnlst (fdefs : expression.efnlst) (vn : list var)
                    (nlst : list var) (next : symgen) (tgm : constr_env)
     : option (fundefs * symgen) :=
       match fdefs with
       | eflnil => ret (Fnil, next)
       | eflcons n1 e1 fdefs' =>
         let (x, next) := gensym next (nNamed "fix_x"%string) in
         let (k', next) := gensym next (nNamed "fix_k"%string) in
         let curr_var := List.hd (1%positive) nlst in
         match e1 with
         | Lam_e n2 e2 =>
           r1 <- cps_cvt e2 (x::vn) k' (next) tgm;;
              let '(ce, next) := r1 : (cps.exp * symgen) in
              r2 <- cps_cvt_efnlst fdefs' vn (List.tl nlst) next tgm;;
                 let '(cfdefs, next) := r2 : (fundefs * symgen) in
                 ret (Fcons curr_var func_tag (x::k'::nil) ce cfdefs, next)
         | _ => None
         end
       end

with cps_cvt_branches (bl : expression.branches_e) (vn : list var) (k : var)
                      (r : var) (next : symgen) (tgm : constr_env)
     : option (list (ctor_tag * exp) * symgen) :=
       match bl with
       | brnil_e => ret (nil, next)
       | brcons_e dc (i, lnames) e bl' =>
         let tg := dcon_to_tag dc tgm in
         let l := List.length lnames in
         rb <- cps_cvt_branches bl' vn k r next tgm;;
            let (cbl, next) := rb : (list (ctor_tag * exp) * symgen) in
            let (vars, next) := gensym_n next (List.rev lnames) in
            let (ctx_p, _) :=
                ctx_bind_proj tg r l (List.hd (1%positive) vars) 0
            in
            let vars_rev := List.rev vars in
            re <- cps_cvt e (vars_rev ++ vn) k next tgm;;
               let '(ce, next) := re : (exp * symgen) in
               ret ((tg, app_ctx_f ctx_p ce)::cbl, next)
       end.

Fixpoint cps_cvt_exps' (es : expression.exps) (vn : list var) (k : var)
         (next : symgen) (tgm : constr_env) :=
  match es with
  | enil => ret (nil, next)
  | econs e es' =>
    r1 <- cps_cvt e vn k next tgm;;
       let '(e', next) := r1 in
       r2 <- cps_cvt_exps' es' vn k next tgm;;
          let (es'', next) := r2 in
          ret (cons e' es'', next)
  end.

Fixpoint cps_cvt_efnlst' (efns : expression.efnlst) (vn : list var) (k : var)
         (next : symgen) (tgm : constr_env) :=
  match efns with
  | eflnil => ret (nil, next)
  | eflcons na e efns' =>
    r1 <- cps_cvt e vn k next tgm;;
       let (e', next) := r1 : (cps.exp * symgen) in
       r2 <- cps_cvt_efnlst' efns' vn k next tgm;;
          let (efns'', next) := r2 in
          ret (cons e' efns'', next)
  end.

Fixpoint cps_cvt_branches' (bs : expression.branches_e) (vn : list var) (k : var)
         (next : symgen) (tgm : constr_env) :=
  match bs with
  | brnil_e => ret (nil, next)
  | brcons_e dc (n, l) e bs' =>
    r1 <- cps_cvt e vn k next tgm;;
       let (e', next) := r1 : (cps.exp * symgen) in
       r2 <- cps_cvt_branches' bs' vn k next tgm;;
          let (bs'', next) := r2 in
          ret (cons e' bs'', next)
  end. 
    

Inductive fresh_var : var -> symgen -> Prop :=
| is_fresh :
    forall v1 v2 nenv,
      (v1 >= v2)%positive ->
      fresh_var v1 (SG (v2, nenv)). 

(* scratch *)
(* how to ensure fresh variables? *)
Inductive cps_cvt_rel : expression.exp -> list var -> var -> cps.exp -> Prop :=
| e_Var :
    forall v vn x k,
      v = (nth vn (N.to_nat x)) ->
      cps_cvt_rel (Var_e x) vn k (cps.Eapp k kon_tag (v::nil))
| e_Lam :
    forall na e1 e1' x1 vn k k1 f,
      cps_cvt_rel e1 (x1::vn) k1 e1' ->
      cps_cvt_rel (Lam_e na e1) vn k (cps.Efun
                                        (Fcons f func_tag (x1::k1::nil) e1' Fnil)
                                        (cps.Eapp k kon_tag (f::nil)))
| e_App :
    forall e1 e1' e2 e2' k k1 k2 x1 x2 vn,
      cps_cvt_rel e1 vn k1 e1' ->
      cps_cvt_rel e2 vn k2 e2' ->
      cps_cvt_rel (App_e e1 e2)
                  vn
                  k
                  (cps.Efun
                     (Fcons k1 kon_tag (x1::nil)
                            (cps.Efun
                               (Fcons k2 kon_tag (x2::nil)
                                      (cps.Eapp x1 func_tag
                                                (x2::k::nil)) Fnil)
                               e2') Fnil)
                     e1')
| e_Let :
    forall na e1 e1' e2 e2' x vn k k1,
      cps_cvt_rel e2 (x::vn) k e2' ->
      cps_cvt_rel e1 vn k1 e1' ->
      cps_cvt_rel (Let_e na e1 e2) vn k (cps.Efun
                                           (Fcons k1 kon_tag (x::nil) e2' Fnil)
                                           e1')
| e_Fix :
    forall fnlst i i' nlst vn k fdefs,
      List.length nlst = efnlength fnlst ->
      cps_cvt_rel_efnlst fnlst (nlst ++ vn) nlst fdefs ->
      i' = (nth nlst (N.to_nat i)) ->
      cps_cvt_rel (Fix_e fnlst i) vn k (cps.Efun fdefs
                                                 (cps.Eapp k kon_tag (i'::nil)))
with cps_cvt_rel_efnlst :
       expression.efnlst -> list var -> list var -> fundefs -> Prop :=
     | e_Eflnil :
         forall vn nlst,
           cps_cvt_rel_efnlst eflnil vn nlst Fnil
     | e_Eflcons :
         forall vn nlst e1 e1' fnlst' fdefs' cvar n1 na x k',
           cps_cvt_rel e1 (x::vn) k' e1' ->
           cps_cvt_rel_efnlst fnlst' vn (List.tl nlst) fdefs' ->
           List.hd_error nlst = Some cvar ->
           cps_cvt_rel_efnlst
             (eflcons n1 (Lam_e na e1) fnlst')
             vn
             nlst
             (Fcons cvar func_tag (x::k'::nil) e1' fdefs').                       


Definition convert_top (ee:ienv * expression.exp) :
  option (ctor_env * name_env * fun_env * ctor_tag * ind_tag * cps.exp) :=
  let '(_, cG, ctag, itag,  dcm) := convert_env (fst ee) in
  let f := (100%positive) in
  let k := (101%positive) in
  let x := (102%positive) in
  r <- cps_cvt (snd ee) nil k (SG (103%positive, n_empty)) dcm;;
    let (e', sg) := r : (cps.exp * symgen) in
    match sg with
      SG (next, nM) =>
      let fenv : fun_env := M.set func_tag (2%N, (0%N::1%N::nil))
                               (M.set kon_tag (1%N, (0%N::nil)) (M.empty _) ) in
      ret (cG, nM, fenv, ctag, itag,
           (cps.Efun
              (Fcons f kon_tag (k::nil) e'
                     (Fcons k kon_tag (x::nil) (Ehalt x) Fnil))
              (cps.Eapp f kon_tag (k::nil))))
    end.

Fixpoint rho_names (rho : exp_eval.env) : list name :=
  match rho with
  | nil => nil
  | cons v rho' =>
    let na := nNamed "rho_elt"%string in
    (na :: (rho_names rho'))
  end.

Fixpoint cps_cvt_val (v : exp_eval.value) (next : symgen)
         (tgm : constr_env) {struct v} : option (cps.val * symgen) :=
  let fix cps_cvt_env vs next tgm :=
       match vs with
       | nil => ret (nil, next)
       | cons v vs' =>
         r1 <- cps_cvt_val v next tgm;;
            let (v', next) := r1 : (val * symgen) in
                r2 <- cps_cvt_env vs' next tgm;;
                   let (vs'', next) := r2 : (list val * symgen) in
                   ret (cons v' vs'', next)
       end
  in
  match v with
  | Con_v dc vs =>
    let c_tag := dcon_to_tag dc tgm in
    r <- cps_cvt_env vs next tgm;;
      let (vs', next) := r : (list val * symgen) in
      ret (Vconstr c_tag (List.rev vs'), next)
  | Clos_v rho na e =>
    r1 <- cps_cvt_env rho next tgm;;
      let (rho', next) := r1 : (list val * symgen) in
      let lnames := rho_names rho in
      let (vars, next) := gensym_n next lnames in
      m <- set_lists vars rho' (M.empty val);;
        let (k1, next) := gensym next (nNamed "k_lam"%string) in
        let (x1, next) := gensym next (nNamed "x_lam"%string) in
        let (f, next) := gensym next na in
        r2 <- cps_cvt e (x1::vars) k1 (next) tgm;;
           let (e', next) := r2 : (cps.exp * symgen) in
           ret (Vfun m (Fcons f func_tag (x1::k1::nil) e' Fnil) f, next)
  | ClosFix_v rho efns n =>
    r1 <- cps_cvt_env rho next tgm;;
      let (rho', next) := r1 : (list val * symgen) in
      let lnames := rho_names rho in
      let (vars, next) := gensym_n next lnames in
      m <- set_lists vars rho' (M.empty val);;
        let (fnlst_length, names_lst) := efnlst_names efns in
        let (nlst, next) := gensym_n next names_lst in
        r2 <- cps_cvt_efnlst efns (nlst ++ vars) nlst next tgm;;
           let (fdefs, next) := r2 : (fundefs * symgen) in
           let i := (nth nlst (N.to_nat n)) in
           ret (Vfun m fdefs i, next)
  | _ => (* TODO *)
    ret (Vint 0, next)
  end.

Fixpoint cps_cvt_env (vs : list exp_eval.value) (next : symgen)
         (tgm : constr_env) : option (list cps.val * symgen) :=
  match vs with
  | nil => ret (nil, next)
  | cons v vs' =>
    r1 <- cps_cvt_val v next tgm;;
       let (v', next) := r1 : (val * symgen) in
       r2 <- cps_cvt_env vs' next tgm;;
          let (vs'', next) := r2 : (list val * symgen) in
          ret (cons v' vs'', next)
  end.


Context (P1 : PostT) (PG : PostGT)
        (pr : prims) (cenv : ctor_env)
        (HPost_con : post_constr_compat P1 P1)
        (HPost_proj : post_proj_compat P1 P1)
        (HPost_fun : post_fun_compat P1 P1)
        (HPost_case_hd : post_case_compat_hd P1 P1)
        (HPost_case_tl : post_case_compat_tl P1 P1)
        (HPost_app : post_app_compat P1 PG)
        (HPost_letapp : post_letapp_compat cenv P1 P1 PG)
        (HPost_letapp_OOT : post_letapp_compat_OOT P1 PG)
        (HPost_OOT : post_OOT P1)
        (Hpost_base : post_base P1)
        (* (HGPost : inclusion P1 PG)  *)
        (Hpost_zero : forall e rho, post_zero e rho P1).   

Definition cps_cvt_correct_e c :=
  forall e e' rho rho' rho_m v v' x k vk vars cnstrs
         next1 next2 next3 next4 next5 cenv,
    eval_env rho e v ->
    cps_cvt_env rho next1 cnstrs = Some (rho', next2) ->
    gensym_n_nAnon next2 (List.length rho') = (vars, next3) ->
    set_lists vars rho' (M.empty val) = Some rho_m ->
    cps_cvt e vars k next3 cnstrs = Some (e', next4) ->
    cps_cvt_val v next1 cnstrs = Some (v', next5) ->
    preord_exp cenv P1 PG c
               ((Eapp k kon_tag (x::nil)), (M.set x v' (M.set k vk (M.empty val))))
               (e', (M.set k vk rho_m)).

Definition cps_cvt_correct_es c :=
    forall es es' rho rho' rho_m vs vs' x k vk vars cnstrs
           next1 next2 next3 next4 next5 cenv,
    Forall2 (fun e v => eval_env rho e v) (exps_to_list es) vs ->
    cps_cvt_env rho next1 cnstrs = Some (rho', next2) ->
    gensym_n_nAnon next2 (List.length rho') = (vars, next3) ->
    set_lists vars rho' (M.empty val) = Some rho_m ->
    cps_cvt_exps' es vars k next3 cnstrs = Some (es', next4) ->
    Forall2 (fun v v' => cps_cvt_val v next1 cnstrs = Some (v', next5)) vs vs' ->
    Forall2
      (fun e' v' =>
         preord_exp cenv P1 PG c
                    ((Eapp k kon_tag (x::nil)),
                     (M.set x v' (M.set k vk (M.empty val))))
                    (e', (M.set k vk rho_m)))
      es' vs'.

Definition cps_cvt_correct_efnlst c :=
  forall efns efns' rho rho' rho_m vfns vfns' x k vk vars cnstrs
         next1 next2 next3 next4 next5 cenv,
    Forall2 (fun p v => let (na, e) := p : (name * expression.exp) in
                        eval_env rho e v) (efnlst_as_list efns) vfns ->
    cps_cvt_env rho next1 cnstrs = Some (rho', next2) ->
    gensym_n_nAnon next2 (List.length rho') = (vars, next3) ->
    set_lists vars rho' (M.empty val) = Some rho_m ->
    cps_cvt_efnlst' efns vars k next3 cnstrs = Some (efns', next4) ->
    Forall2 (fun v v' => cps_cvt_val v next1 cnstrs = Some (v', next5)) vfns vfns' ->
    Forall2
      (fun e' v' =>
         preord_exp cenv P1 PG c
                    (e', (M.set k vk rho_m))
                    ((Eapp k kon_tag (x::nil)),
                     (M.set x v' (M.set k vk (M.empty val)))))
      efns' vfns'.


Definition cps_cvt_correct_branches c :=
  forall bs bs' rho rho' rho_m vs vs' x k vk vars cnstrs
         next1 next2 next3 next4 next5 cenv,
    Forall2 (fun p v => let '(dc, (n, l), e) := p in
                        eval_env rho e v) (branches_as_list bs) vs ->
    cps_cvt_env rho next1 cnstrs = Some (rho', next2) ->
    gensym_n_nAnon next2 (List.length rho') = (vars, next3) ->
    set_lists vars rho' (M.empty val) = Some rho_m ->
    cps_cvt_branches' bs vars k next3 cnstrs = Some (bs', next4) ->
    Forall2 (fun v v' => cps_cvt_val v next1 cnstrs = Some (v', next5)) vs vs' ->
    Forall2
      (fun e' v' =>
         preord_exp cenv P1 PG c
                    (e', (M.set k vk rho_m))
                    ((Eapp k kon_tag (x::nil)),
                     (M.set x v' (M.set k vk (M.empty val)))))
      bs' vs'.

Lemma cps_cvt_correct:
  forall k,
    (cps_cvt_correct_e k) /\
    (cps_cvt_correct_es k) /\
    (cps_cvt_correct_efnlst k) /\
    (cps_cvt_correct_branches k).
Proof.
  intros k. eapply my_exp_ind.
  - intros. inv H.
    simpl in H3. inv H3.
    eapply preord_exp_app_compat.
    + eapply HPost_app. 
    + eapply HPost_OOT.
    + unfold preord_var_env.
      intros v1 Hgetv1. rewrite M.gso in Hgetv1.
      rewrite M.gss in Hgetv1. inv Hgetv1.
      eexists. rewrite M.gss. split.
      reflexivity.
      eapply preord_val_refl; admit. admit. 

Abort. 

  
(* cenv needs to related to dcon? *)
Lemma cps_cvt_correct':
  forall e m rho rho' rhomap x k vk e' v v' v'' v''' penv cenv
         vars cnstrs next1 next2 next3 next4 next5,
    eval_env rho e v ->
    cps_cvt_env rho next1 cnstrs = Some (rho', next2) ->
    gensym_n_nAnon next2 (List.length rho') = (vars, next3) ->
    set_lists vars rho' (M.empty val) = Some rhomap ->
    cps_cvt e vars k next3 cnstrs = Some (e', next4) ->
    cps_cvt_val v next1 cnstrs = Some (v', next5) ->
    bstep_e penv cenv (M.set x v' (M.set k vk (M.empty val))) (Eapp k kon_tag (x::nil)) v'' m ->
    exists n, bstep_e penv cenv (M.set k vk rhomap) e' v''' n /\
    exists f, (Alpha_conv_val v'' v''' f).
Proof.
  intros e. 
  eapply my_exp_ind.
  
Abort. 
  
(* testing code *)

From CertiCoq.L7 Require Import L6_to_Clight.

(* Added for L6_evaln *)
Require Import exceptionMonad.

Inductive bigStepResult {Term Value : Type} : Type :=
    Result : Value -> bigStepResult 
  | OutOfTime : Term -> bigStepResult 
  | Error : string -> option Term -> bigStepResult.

Definition L6_evaln_fun n p : @bigStepResult (env * exp) cps.val :=
  let '((penv, cenv, nenv, fenv), (rho, e)) := p
  : ((prims * ctor_env * name_env * fun_env) * (env * cps.exp)) in
  match bstep_f penv cenv rho e n with
  | exceptionMonad.Exc s => Error s None
  | Ret (inl t) => OutOfTime t
  | Ret (inr v) => Result v
  end.

Definition print_BigStepResult_L6 p n :=
  let '((penv, cenv, nenv, fenv), (rho, e)) :=
      p : ((M.t (list cps.val -> option cps.val) * ctor_env * name_env * fun_env) *
           (M.t cps.val * cps.exp)) in
  L7.L6_to_Clight.print (
      match (bstep_f penv cenv rho e n) with
      | exceptionMonad.Exc s => s
      | Ret (inl t) =>
        let (rho', e') := t : (env * cps.exp) in
        "Out of time:" ++ (show_cenv cenv) ++ (show_env nenv cenv false rho') ++
                       (show_exp nenv cenv false e')
      | Ret (inr v) => show_val nenv cenv false v
      end).

Definition print_BigStepResult_L6Val p :=
  let '((penv, cenv, nenv, fenv), (rho, v)) :=
      p : ((M.t (list cps.val -> option cps.val) * ctor_env * name_env * fun_env) *
           (M.t cps.val * cps.val)) in
  L7.L6_to_Clight.print ((show_cenv cenv) ++ (show_env nenv cenv false rho) ++
                                          (show_val nenv cenv false v)).

(*
Quote Recursively Definition test1_program :=
  ((fun x =>
      match x with
      | nil => 3%nat
      | cons h x' => h
      end) ((1%nat)::nil)).

Definition id_f (x : nat) := x.

Definition match_test (l : list nat) :=
  match l with
  | nil => false
  | cons el l' => true
  end.

Quote Recursively Definition test2_program := (match_test (1%nat::nil)).

Definition add_test := Nat.add 1%nat 0%nat.

Fixpoint id_nat (n : nat) :=
  match n with
  | O => O
  | S n' => S (id_nat n')
  end.

Definition plus_1 (l : list nat) :=
  let fix plus_1_aux l k :=
    match l with
    | nil => k nil
    | cons n l' => plus_1_aux l' (fun s => k ((Nat.add n 1%nat)::s))
    end
  in
  plus_1_aux l (fun s => s).

Definition hd_test := (@List.hd nat 0%nat (1%nat::nil)).

Definition let_simple :=
  let x := 3%nat in Nat.add x 0%nat.

Quote Recursively Definition test3_program := hd_test.

Quote Recursively Definition test4_program :=
  (List.hd 0%nat (plus_1 (0%nat::1%nat::nil))).

Quote Recursively Definition test5_program := (List.hd_error (false::nil)).


(* Quote Recursively Definition test3_program := *)


Definition test_eval :=
  Eval native_compute in (translateTo (cTerm certiL4) test5_program).

Print test_eval.

Definition test :=
  match test_eval with
  | exceptionMonad.Ret p => p
  | exceptionMonad.Exc s => (nil, expression.Prf_e)
  end.

Definition test_result :=
  match (convert_top test) with
  | Some (cenv, nenv, _, ctg, itg, e) =>
    let pr := cps.M.empty (list val -> option val) in
    let fenv := cps.M.empty fTyInfo in
    let env := cps.M.empty val in
    print_BigStepResult_L6 ((pr, cenv, nenv, fenv), (env, e)) 250%nat
  | None =>
    L7.L6_to_Clight.print ("Failed during comp_L6")
  end.

Require Import ExtrOcamlBasic.
Require Import ExtrOcamlString.
Require Import ExtrOcamlZInt.
Require Import ExtrOcamlNatInt.

Extract Inductive Decimal.int =>
unit [ "(fun _ -> ())" "(fun _ -> ())" ] "(fun _ _ _ -> assert false)".

Extract Constant L6_to_Clight.print =>
"(fun s-> print_string (String.concat """" (List.map (String.make 1) s)))".


Extract Constant   varImplDummyPair.varClassNVar =>
" (fun f (p:int*bool) -> varClass0 (f (fst p)))".

Extraction "test1.ml" test_result.
*)
