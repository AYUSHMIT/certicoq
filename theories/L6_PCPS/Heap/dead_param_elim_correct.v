From CertiCoq.L6 Require Import cps cps_util set_util identifiers ctx Ensembles_util
     List_util functions tactics map_util.

From CertiCoq.L6.Heap Require Import heap heap_defs heap_equiv space_sem
     cc_log_rel dead_param_elim_rel GC log_rel_defs log_rel_post_cc.

From Coq Require Import ZArith.Znumtheory Relations.Relations Arith.Wf_nat
                        Lists.List MSets.MSets MSets.MSetRBT Numbers.BinNums
                        NArith.BinNat PArith.BinPos Sets.Ensembles Omega Permutation.

Import ListNotations.

Open Scope ctx_scope.
Open Scope fun_scope.
Close Scope Z_scope.

Module DeadParamCorrect (H : Heap).

  Module LR := LogRelPostCC H.
  
  Import H LR LR.LRDefs LR.LRDefs.Sem.GC LR.LRDefs.Sem.GC.Equiv
         LR.LRDefs.Sem.GC.Equiv.Defs LR.LRDefs.Sem.

  
  Definition Pre : IInv :=
    fun c1 c2 => 
      let '(H1, rho1, e1) := c1 in
      let '(H2, rho2, e2) := c2 in
      size_heap H2 <= size_heap H1. 

  Definition Post : Inv :=
    fun c p1 p2 =>
      let '(c1, m1) := p1 in
      let '(c2, m2) := p1 in
      c2 <= c1 /\ m2 <= m1. 

  Definition PreG : GIInv :=
    fun _ _ _ _ c1 c2 => 
      let '(H1, rho1, e1) := c1 in
      let '(H2, rho2, e2) := c2 in
      size_heap H2 <= size_heap H1. 

  Definition PostG : GInv :=
    fun _ _ c p1 p2 =>
      let '(c1, m1) := p1 in
      let '(c2, m2) := p1 in
      c2 <= c1 /\ m2 <= m1.


  (** * Lemmas about space bound preservation *)

  Lemma InvBase e1 e2 :
    InvCostBase_w Post Pre e1 e2. 
  Proof.
    intros H1 H2 rho1 rho2 c1 c2 Hpre Hleq. unfold Pre, Post in *.
    split; omega.
  Qed.
  
  Lemma InvCtx C e1 e2 :
    InvCtxCompat Post Post C C e1 e2. 
  Proof.
    intros H1 H2 H1' H2' rho1 rho2 rho1' rho2' c1 c2 c1' c2' m1 m2 Hpost Hleq Hctx1 Hctx2.    
    unfold Pre, Post in *. omega. 
  Qed. 

  Lemma IInvCtx C e1 e2 :
    IInvCtxCompat Pre Pre C C e1 e2. 
  Proof.
    intros H1 H2 H1' H2' rho1 rho2 rho1' rho2' c1 c2 Hpre Hctx1 Hctx2.    
    unfold Pre, Post in *. erewrite ctx_to_heap_env_CC_size_heap at 1; try eassumption.
    erewrite ctx_to_heap_env_CC_size_heap with (H1 := H1) (H2 := H1'); try eassumption.
    omega. 
  Qed. 


  (** * Drop invariant and lemmas *)

  
  Definition drop_invariant (drop : var -> option (list bool)) rho1 rho2 :=
    exists B1 B2, (* There exists function blocks B1 B2 -- i.e. the functions defined at the beginning of the programs *)
      unique_bindings_fundefs B1 /\ (* that have unique binders *)
      closed_fundefs B1 /\ (* are closed *) 
      Drop_fundefs drop B1 B2 /\ (* are in Drop_fundefs relation *)
      domain drop <--> name_in_fundefs B1 /\ (* The domain of drop contains exactly the names of the functions in map *)
      forall f bs, drop f = Some bs -> (* and all the variables in the domain of drop. TODO write with domain *)
              M.get f rho1 = Some (FunPtr B1 f) /\
              M.get f rho2 = Some (FunPtr B2 f).

  (* This is the old definition, keeping it for reference *)
  (* exists B1 f1 B2 f2 t xs1 e1 xs2 e2 S, *)
  (*   find_def f1 B1 = Some (t, xs1, e1) /\ *)
  (*   find_def f2 B2 = Some (t, xs2, e2) /\ *)
  (*   Drop_fundefs drop B1 B2 /\ *)
  (*   Drop_params xs1 bs xs2 S /\ *)
  (*   Drop_body drop S e1 e2. *)

  (* Instead of the old drop_invariant, we can prove this lemma *)
  Lemma Drop_fundefs_fun_in_fundef drop B1 B2 f ft xs1 e1 :
    Drop_fundefs drop B1 B2 ->
    find_def f B1 = Some (ft, xs1, e1) ->
    exists bs S xs2 e2,
      find_def f B2 = Some (ft, xs2, e2) /\
      drop f = Some bs /\
      Drop_params xs1 bs xs2 S /\
      Drop_body drop S e1 e2.
  Proof.
    intros Hdrop.
    revert f ft xs1 e1; induction Hdrop; intros f ft' xs1 e1 Hin; inv Hin. 
    destruct (cps.M.elt_eq f g); subst. 
    + inv H3. 
      do 4 eexists. split.
      simpl. rewrite Coqlib.peq_true. reflexivity.
      repeat split; eassumption. 
    + edestruct IHHdrop as (b1 & S1 & xs2 & e2 & Hin & Hand). eassumption.
      do 4 eexists. split.
      simpl. rewrite Coqlib.peq_false; eassumption.
      eassumption.
  Qed. 
    
      
  Lemma drop_invariant_extend drop rho1 rho2 x v1 v2 :
    ~ x \in domain drop ->
    drop_invariant drop rho1 rho2 ->
    drop_invariant drop (M.set x v1 rho1) (M.set x v2 rho2).
  Proof.
    intros Hnin Hinv. unfold drop_invariant.
    destruct Hinv as (B1 & B2 & Hun & Hclo & Hdrop & Hdom & Hyp).
    do 2 eexists. do 4 (split; [ eassumption |]). intros f bs Hget.
    setoid_rewrite M.gso. eapply Hyp. eassumption. 
    
    intros Hc; subst.
    eapply Hnin. eexists bs. eassumption.
    intros Hc; subst.
    eapply Hnin. exists bs. eassumption.
  Qed. 
  
  Lemma drop_body_occurs_free S drop e1 e2 : 
    Drop_body drop S e1 e2 ->
    occurs_free e2 \subset occurs_free e1 \\ S.
  Proof with (now eauto with Ensembles_DB).
    revert e2.
    induction e1 using exp_ind'; intros e2 Hdrop; inv Hdrop;
      try normalize_occurs_free; try normalize_occurs_free;
        try rewrite Setminus_Union_distr.
    - (* Econstr *)
    eapply Included_Union_compat. 
    + eapply Included_Setminus. 
      eapply Disjoint_sym. eapply Disjoint_sym in H4. 
      eapply Disjoint_Union_l. eassumption. 
      eapply Included_refl. 
    + rewrite Setminus_Union.  
      rewrite Union_commut. rewrite <- Setminus_Union. 
      eapply Included_Setminus_compat.
      eapply IHe1. eassumption. 
      eapply Included_refl.
    - inv H3. normalize_occurs_free.
      eapply Included_Setminus. 
      eapply Disjoint_sym.  
      apply Disjoint_Singleton_r in H1. 
      eapply Disjoint_Union_l. eassumption. 
      eapply Included_refl.
    - inv H3. destruct y as [c' e2]. destruct H2 as [Heq1 Hdrop]. simpl in Heq1; subst.
      simpl in *. normalize_occurs_free.
      eapply Union_Included; [| eapply Union_Included ].
      + eapply Included_Union_preserv_l.
        eapply Included_Setminus.  
        apply Disjoint_Singleton_l. intros Hc. eapply H1; now left.
        reflexivity.
      + eapply Included_trans. eapply IHe1. eassumption.
        rewrite Setminus_Union_distr...
      + eapply Included_trans. eapply IHe0.
        constructor; eassumption.
        rewrite Setminus_Union_distr...
    - (* Eproj *)
      eapply Included_Union_compat. 
      + eapply Included_Setminus. 
        eapply Disjoint_sym.  
        apply Disjoint_Singleton_r in H5. 
        eapply Disjoint_Union_l. eassumption. 
        eapply Included_refl. 
      + rewrite Setminus_Union. 
        rewrite Union_commut. rewrite <- Setminus_Union. 
        eapply Included_Setminus_compat. eapply IHe1. eassumption. 
        eapply Included_refl. 
    - (* Eapp unknown *)
      rewrite !occurs_free_Eapp at 1.
      rewrite Setminus_Union_distr.
      eapply Included_Union_compat. 
      + eapply Included_Setminus; [| reflexivity ].
        eapply Disjoint_Included_r; [| eassumption ]...
      + eapply Included_Setminus; [| reflexivity ].
        apply Disjoint_Singleton_r in H2. 
        eapply Disjoint_sym. eapply Disjoint_Union_l. eassumption.
    - (* Eapp known *)
      eapply Included_Union_compat. 
      + clear H2. induction H5.
        rewrite !FromList_nil at 1.
        rewrite Setminus_Empty_set_abs_r. reflexivity.
        
        normalize_sets. eapply Included_trans. eapply IHDrop_args.
        now eauto with Ensembles_DB.

        rewrite !FromList_cons at 1.
        rewrite Setminus_Union_distr. eapply Included_Union_compat.
        * eapply Included_Setminus. 
          eapply Disjoint_sym.  
          apply Disjoint_Singleton_r in H. 
          eapply Disjoint_Union_l. eassumption. 
          eapply Included_refl.
        * eassumption.
      + eapply Included_Setminus. 
        eapply Disjoint_sym.  
        apply Disjoint_Singleton_r in H4. 
        eassumption. reflexivity.
    - (* Eprim *)
      eapply Included_Union_compat. 
      + eapply Included_Setminus. 
        eapply Disjoint_sym. eapply Disjoint_sym in H4. 
        eapply Disjoint_Union_l. eassumption. 
        eapply Included_refl. 
      + rewrite Setminus_Union. 
        rewrite Union_commut. rewrite <- Setminus_Union. 
        eapply Included_Setminus_compat. eapply IHe1. eassumption.
        reflexivity.
    - (* Ehalt *)
      rewrite !occurs_free_Ehalt at 1.
      eapply Included_Setminus. 
      eapply Disjoint_sym.  
      apply Disjoint_Singleton_r in H0. 
      eapply Disjoint_Union_l. eassumption. 
      eapply Included_refl.
  Qed. 

  Lemma drop_invariant_reach1 drop rho1 rho2 : (* Zoe TODO *)
    drop_invariant drop rho1 rho2 -> 
    env_locs rho1 (domain drop) <--> Empty_set _. 
  Proof.
  Abort. 

  Lemma drop_invariant_reach2 drop rho1 rho2 : (* Zoe TODO *)
    drop_invariant drop rho1 rho2 -> 
    env_locs rho2 (domain drop) <--> Empty_set _. 
  Proof.
  Abort.
  
  Lemma drop_invariant_reach2_setminus S drop rho1 rho2 : (* Zoe TODO *)
    drop_invariant drop rho1 rho2 -> 
    env_locs rho2 (S \\ dropped_funs drop) <--> env_locs rho2 S. 
  Proof with (now eauto with Ensembles_DB).
    intros (B1 & B2 & Hun & Hclo & Hdrop & Hyp).
    split.
    eapply env_locs_monotonic...

    intros l [x [Hin Hget]].
    destruct (M.get x rho2) eqn:Hgetx; try contradiction.

    assert (Hnin : ~ x \in dropped_funs drop). 
    { intros [bs [Hc _]]. eapply Hyp in Hc. inv Hc. 
      repeat subst_exp. inv Hget. }
    eapply get_In_env_locs; try eassumption.
    split; eauto.
  Qed.
  
  Inductive Forall2_assym {A B : Type} (P : A -> B -> Prop) :
    list A -> list B -> list bool -> Prop :=
  | Forall2_assym_nil : Forall2_assym P [] [] []
  | Forall2_assym_cons1 :
      forall x xs bs ys,
        Forall2_assym P xs ys bs ->
        Forall2_assym P (x :: xs) ys (false :: bs)
  | Forall2_assym_cons2 :
      forall x xs bs y ys,
        Forall2_assym P xs ys bs ->
        P x y -> 
        Forall2_assym P (x :: xs) (y :: ys) (true :: bs).
  

  Lemma env_rel_add_args_dropped Pre Post k H1 rho1 H2 rho2 b xs1 xs2 bs S vs1 :
    (forall j, (H1, rho1) ⋞ ^ (FromList xs1 \\ S; k; j; Pre; Post; b) (H2, rho2)) ->
    Drop_args S xs1 bs xs2 ->

    getlist xs1 rho1 = Some vs1 ->

    exists vs2,
      getlist xs2 rho2 = Some vs2 /\
      Forall2_assym (fun v1 v2 => forall j, (Res (v1, H1)) ≺ ^ ( k ; j ; Pre ; Post ; b ) (Res (v2, H2))) vs1 vs2 bs.
  Proof with (now eauto with Ensembles_DB).
    intros Hrel Hdrop. revert vs1. induction Hdrop; intros vs1 Hget.
    - eexists []. split. reflexivity. simpl in Hget. inv Hget.
      constructor. 
    - simpl in Hget.
      destruct (M.get x rho1) eqn:Hget1; [| congruence ].
      destruct (getlist xs rho1) eqn:Hgetlist; [| congruence ].
      inv Hget.
      
      edestruct IHHdrop as [vs2 [Hget2 Hall]]; [| reflexivity | ]. 

      intros j. eapply env_log_rel_P_antimon. eapply Hrel.
      normalize_sets. rewrite Setminus_Union_distr... 
      
      eexists; split; eauto.
      econstructor. eassumption. 
    - simpl in Hget.
      destruct (M.get x rho1) eqn:Hget1; [| congruence ].
      destruct (getlist xs rho1) eqn:Hgetlist; [| congruence ].
      inv Hget. 
      edestruct (Hrel 0) as [v2 [Hgetx2 Hvrel]]; [| eassumption | ].
      constructor; eauto. 
      normalize_sets. constructor; eauto.

      edestruct IHHdrop as [vs2 [Hget2 Hall]]; [| reflexivity | ]. 

      intros j.
      eapply env_log_rel_P_antimon. eapply Hrel.
      normalize_sets...
      
      eexists (v2 :: vs2). 
      split. simpl. rewrite Hgetx2, Hget2. reflexivity.
      constructor. eassumption.
      intros j.
      edestruct (Hrel j) as [v2' [Hgetx2' Hvrel']]; [| eassumption | ].
      constructor; eauto. normalize_sets...
      repeat subst_exp. 
      eassumption. 
  Qed. 
  
  Lemma env_rel_set_params_dropped Pre Post k H1 rho1 rho1' H2 rho2 b xs1 xs2 bs P S vs1 vs2 :
    (forall j, (H1, rho1) ⋞ ^ (P ; k; j; Pre; Post; b) (H2, rho2)) ->

    Drop_params xs1 bs xs2 S ->
    setlist xs1 vs1 rho1 = Some rho1' ->
    
    Forall2_assym (fun v1 v2 : value => forall j, Res (v1, H1) ≺ ^ (k; j; Pre; Post; b) Res (v2, H2)) vs1 vs2 bs ->

    exists rho2',
      setlist xs2 vs2 rho2 = Some rho2' /\
      (forall j, (H1, rho1') ⋞ ^ (P :|: FromList xs1 \\ S ; k; j; Pre; Post; b) (H2, rho2')).    
  Proof with (now eauto with Ensembles_DB).
    intros Hrel Hdrop. revert vs1 vs2 rho1 rho1' Hrel. induction Hdrop; intros vs1 vs2 rho1 rho1' Hrel Hset1 Hall.
    - inv Hall. simpl in Hset1. inv Hset1. 
      eexists rho2. split. reflexivity.
      intros j. normalize_sets.
      rewrite Union_Empty_set_neut_r, Setminus_Empty_set_neut_r. eapply Hrel.

    - simpl in Hset1. destruct vs1 as [ | v1 vs1 ]; try congruence. 
      destruct (setlist xs vs1 rho1) as [rho1'' |] eqn:Hsetlist1; [| congruence ]. inv Hset1.
      inv Hall.
      edestruct IHHdrop as [rho2' [Hsetlist2 Henv]]. 
      eassumption. eassumption. eassumption.
      
      exists rho2'. split. eassumption.

      intros j. 
      eapply env_log_rel_P_set_not_in_S_l.      

      eapply env_log_rel_P_antimon. eapply Henv.

      normalize_sets.
      rewrite !Setminus_Union_distr. 
      rewrite (Setminus_Included_Empty_set [set x] (x |: S))...
      
      intros Hc. inv Hc. eapply H0. now left. 
      
    - simpl in Hset1. destruct vs1 as [ | v1 vs1 ]; try congruence. 
      destruct (setlist xs vs1 rho1) eqn:Hsetlist1; [| congruence ]. inv Hset1.
      inv Hall.
      edestruct IHHdrop as [rho2' [Hsetlist2 Henv]]. 
      eassumption. eassumption. eassumption.

      exists (M.set x y rho2'). split.
      simpl. rewrite Hsetlist2. reflexivity.
      intros j. eapply env_log_rel_P_set.
      
      eapply env_log_rel_P_antimon. eapply Henv.
      normalize_sets. 
      rewrite !Setminus_Union, !Setminus_Union_distr.
      
      rewrite (Setminus_Included_Empty_set [set x] (S :|: [set x]))...
      eapply H6. 
  Qed.                
    

  (* Easy lemma about Drop_fundefs *)
  Lemma Drop_fundefs_name_in_fundefs drop B1 B2 : 
    Drop_fundefs drop B1 B2 ->
    name_in_fundefs B1 <--> name_in_fundefs B2.
  Proof.
  Admitted. 

  Lemma Drop_fundefs_drop_invariant B1 B2 drop rho1 rho2:
    unique_bindings_fundefs B1 ->
    closed_fundefs B1 ->
    Drop_fundefs drop B1 B2 ->
    domain drop <--> name_in_fundefs B1 -> 
    drop_invariant drop (def_funs B1 B1 rho1) (def_funs B2 B2 rho2).  
  Proof.
    intros Hyp Hclo Hdrop Heq.
    eexists B1, B2.  repeat (split; [ eassumption |]).
    intros f1 bs1 Hd. split; eapply def_funs_eq; try reflexivity.
    eapply Heq. eexists; eauto. 
    rewrite <- Drop_fundefs_name_in_fundefs; [| eassumption  ]. 
    eapply Heq. eexists; eauto. 
  Qed. 


  Instance Decidable_dropped_funs drop :
    Decidable (dropped_funs drop).
  Admitted. 
  (** Lemma about defining a block of dropped functions in the environment (correctness of Drop_fundefs relation) *)
  
  (*  This lemma will be used for the toplevel correctness theorem, when we first define the toplevel functions and
      also when we redefine them in the environment in the known function application case.
      we assume that the theorem for Drop_body fold for smaller step-indices
      (These two proofs are by mutual induction, since the two definitions are mutually recursive ). 
   *)
 
  (* This only talks about the functions that are related by Drop_funs but are  not in dropped_funs drop, i.e. they
     do not have any parameters dropped. For these we have two show that they are related by the environment relation.
     To cover for the case of functions that have parameters dropped we have to show that def_funs of Drop_fundefs
     satisfy the drop_invariant (ignore for now I'm planning to change this in the next couple of days.) 
   *)


  Lemma Drop_params_all_true xs1 bs xs2 S :
    Drop_params xs1 bs xs2 S -> 
    Forall (fun x => x = true) bs ->
    xs1 = xs2 /\ S <--> Empty_set _.
  Proof. (* TODO Katja *) 
  Admitted.

  Lemma def_funs_binding_in_map S B1' B1 rho1 :
    binding_in_map S rho1 ->
    binding_in_map (name_in_fundefs B1' :|: S) (def_funs B1' B1 rho1).
  Proof.
    intros Hin. induction B1'; simpl. 
    - eapply binding_in_map_antimon.
      rewrite <- Union_assoc, Union_commut. reflexivity.  
      eapply binding_in_map_set.
      eassumption. 
    - eapply binding_in_map_antimon.
      rewrite Union_Empty_set_neut_l. 
      reflexivity. eassumption.
  Qed.
  
  Lemma dead_param_elim_fundefs_correct k
        (** We assume the IH of the main proof. *)
        (IHexp : forall m : nat,
            m < k ->
            forall (j : nat) (H1 : heap block)
              (rho1 : env) (e1 : exp) (H2 : heap block)
              (rho2 : env) (e2 : exp) (b : Inj)
              (drop : var -> option (list bool))
              (S : Ensemble var),
              (forall j0 : nat,
                  (H1, rho1) ⋞ ^ (occurs_free e1 \\ S \\ dropped_funs drop; m; j0; PreG; PostG; b) (H2, rho2)) ->
              closed (reach' H1 (env_locs rho1 (occurs_free e1)))
                     H1 ->
              drop_invariant drop rho1 rho2 ->
              binding_in_map (occurs_free e1) rho1 ->
              unique_bindings e1 ->
              Disjoint var (domain drop) (bound_var e1) ->
              Disjoint var (occurs_free e1) (bound_var e1) ->
              Drop_body drop S e1 e2 ->
              (H1, rho1, e1) ⪯ ^ (m; j; Pre; PreG; Post; PostG) (H2, rho2, e2)) :
    forall B1 B1' B2 B2' P
      H1 rho1  H2 rho2 (* source and target conf *)
      b (* location renaming *)
      drop, (* dropper function *)
      (* assume that two environments where initially related *)
      (forall j, (H1, rho1) ⋞ ^ (P \\ name_in_fundefs B1; k ; j; PreG ; PostG ; b) (H2, rho2)) ->
      (* free variable assumptions *)
      closed_fundefs B1' ->
      unique_bindings_fundefs B1'  ->
      Disjoint var (occurs_free_fundefs B1') (bound_var_fundefs B1') ->
      (* The drop invariant holds *)
      domain drop <--> name_in_fundefs B1' -> 
      (* Drop_fundefs relation *)
      Drop_fundefs drop B1' B2' ->
      (* Because of the way def_funs is defined we need to generalize over both of its two first arguments
       the be able to do the proof. We might need more *)
      Drop_fundefs drop B1 B2 ->
      (* this is useful to relate the names of the functions. Could have : name_in_fundefs B1 <--> name_fundefs B2 *)

      (forall j, (H1, def_funs B1 B1' rho1) ⋞ ^ (P \\ dropped_funs drop ; k ; j; PreG ; PostG ; b) (H2, def_funs B2 B2' rho2)).
  Proof with now eauto with Ensembles_DB.
    (* induction at the step index we will used it when redefining
       functions in the environment after upon function entry *)
    induction k as [k IHk] using lt_wf_rec1; 
      (* induction at the mut. functions block *)
      intros B1;
      induction B1;
      intros B1' B2 B2' P H1 rho1  H2 rho2 b drop Hrel Hclos Hun
             Hdis Hdinv Hdrop' Hdrop; inv Hdrop.
    - (* Cons case - Hard *)
      simpl def_funs.

      (* Check whether v belongs to (dropped_funs drop).*)
      edestruct (Decidable_dropped_funs drop).
      destruct (Dec v) as [Hdin | Hdnin ]. 
      + (* Case 1 : it is dropped *)
        intros j.
        eapply env_log_rel_P_set_not_in_S_l. 
        eapply env_log_rel_P_set_not_in_S_r. 
        admit. (* XXX Zoe arg *)
        eapply env_log_rel_P_antimon.
        eapply IHB1 with (P := P \\ [set v]).
        setoid_rewrite Setminus_Union. eassumption.
        eassumption. eassumption. eassumption.
        eassumption. eassumption. eassumption.
        rewrite !Setminus_Union...
        intros Hc. inv Hc. contradiction.
        intros Hc. inv Hc. contradiction.
      + (* Case 2 : it's not dropped *)
        intros j. eapply env_log_rel_P_set.
        * eapply env_log_rel_P_antimon.
          eapply IHB1 with (P := P \\ [set v]).
          setoid_rewrite Setminus_Union. eassumption.
          eassumption. eassumption. eassumption.
          eassumption. eassumption. eassumption.
          rewrite !Setminus_Union...
        * rewrite val_rel_eq.
          intros H1' H2' rho1' ft xs1 e1 vs1 vs2 b'
                 Hfind1 Hset1 Hlen.
          edestruct Drop_fundefs_fun_in_fundef
            as [bs' [S' [xs2 [e2 [Hfind2 [Hdeq' [Hdparm Hdbody]]]]]]].
          eapply Hdrop'. eassumption. 
          repeat subst_exp.
          
          assert (Hall : Forall (fun x => x = true) bs'). 
          { eapply Forall_impl with (P := fun x => ~ x = false).
            intros a Heq. now destruct a; eauto.
            eapply Forall_Exists_neg.
            intros Hc. eapply Hdnin.
            exists bs'. split; eassumption. }
          
          edestruct Drop_params_all_true; try eassumption.
          subst.
          
          exists xs2, e2.  

          edestruct
            (setlist_length3 (def_funs B2' B2' (M.empty _)) xs2 vs2) as [rho2' Hset2].
          rewrite <- Hlen. eapply setlist_length_eq. 
          eassumption.

          exists rho2'. split. 
          eassumption. split. eassumption.

          { intros i Hlt Hallv.
            split.
            - (* bounds TODO Zoe *)
              admit. 
            - intros j'.
              eapply IHexp.
              + eassumption.
              + intros j''.
                eapply env_log_rel_P_setlist_l;
                  [ | | eassumption | eassumption ].
                * (* Apply IHk *)
                  { eapply IHk.
                    - eassumption.
                    - intros m Hlt'.
                      eapply IHexp. omega. 
                    - admit. (* TODO Zoe *)
                    - eassumption.
                    - eassumption.
                    - eassumption.
                    - eassumption.
                    - eassumption.
                    - eassumption. } 
                * eapply Hallv.
              + admit. (* TODO Zoe *)
              + admit. (* drop_invariant preserved by setlist. Zoe add lemma *)
              + eapply binding_in_map_antimon.
                eapply logical_relations.occurs_free_closed_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.
                eapply binding_in_map_setlist; [| eassumption ].
                eapply binding_in_map_antimon; [| eapply def_funs_binding_in_map ].
                rewrite Union_Empty_set_neut_r. reflexivity. 
                intros x Hin. inv Hin. 
              + eapply unique_bindings_fun_in_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.
              + rewrite Hdinv.
                eapply Disjoint_sym.
                eapply unique_bindings_fun_in_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.
              + eapply Disjoint_Included_l.
                eapply logical_relations.occurs_free_closed_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.
                eapply Disjoint_sym.
                eapply Union_Disjoint_r.

                eapply unique_bindings_fun_in_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.

                eapply unique_bindings_fun_in_fundefs.
                eapply find_def_correct. eassumption.
                eassumption.
              + eassumption. }
    - simpl def_funs.
      intros j. eapply env_log_rel_P_antimon.
      eapply Hrel.
      simpl... 
  Admitted. 

  (** Correctness of drop_body relation *)  
  Lemma dead_param_elim_correct
        k j (* step and heap indices *)
        H1 rho1 e1 H2 rho2 e2 (* source and target conf *)
        b (* location renaming *)
        drop (* dropper function *)
        S (* dropped variables *) :

    (forall j, (H1, rho1) ⋞ ^ (occurs_free e1 \\ S \\ dropped_funs drop ; k ; j; PreG ; PostG ; b) (H2, rho2)) ->
    (* heap is well-formed in S *)
    closed (reach' H1 (env_locs rho1 (occurs_free e1))) H1 ->
    
    (* invariant about dropped function names *)
    drop_invariant drop rho1 rho2 -> 
    
    (* Assumptions about variable names *)
    binding_in_map (occurs_free e1) rho1 ->
    unique_bindings e1 ->
    Disjoint _ (domain drop) (bound_var e1) ->
    Disjoint _ (occurs_free e1) (bound_var e1) -> 
    
    
    (* e2 is the dropping of e1 *)
    Drop_body drop S e1 e2 ->
    (* The source and target are related *)
    (H1, rho1, e1) ⪯ ^ ( k ; j ; Pre ; PreG ; Post ; PostG ) (H2, rho2, e2).
  Proof with now eauto with Ensembles_DB.
    revert j H1 rho1 e1 H2 rho2 e2 b drop S;
      induction k as [k IHk] using lt_wf_rec1;
      intros j H1 rho1 e1 H2 rho2 e2 b drop S Hrel Hclos Hdinv
             Hbin Hun Hdis1 Hdis2 Hdrop.
    
    assert (Hfv_sub : occurs_free e2 \subset occurs_free e1 \\ S) by (eapply drop_body_occurs_free; eauto).
    
    inv Hdrop. 
    - (* ----------- Econstr ----------- (3) *)
      eapply exp_rel_constr_compat. 
      + eapply InvCtx.
      + eapply IInvCtx.
      + eapply InvBase.
      + eassumption.
      + eapply closed_reach_monotonic. eapply env_rel_closed_reach2.
        eassumption. eapply binding_in_map_antimon; [| eassumption ]...
        rewrite drop_invariant_reach2_setminus; [| eassumption ]. eapply env_locs_monotonic. eassumption. 
      + intros j'. setoid_rewrite Setminus_Union in Hrel. 
        eapply var_log_rel_Forall2.   
        * eapply Hrel.
        * normalize_occurs_free. eapply Included_Setminus.
          eassumption. now eauto with Ensembles_DB. 
      + intros vs1 vs2 l1 l2 H1' H2' Hleq Hloc1 Hloc2 Halloc1 Halloc2 HForall2 j'. 
        eapply IHk with (S := S) (drop := drop) (b :=  b { l1 ~> l2 }).
        * simpl in *. omega. 
        * intros j''.
          eapply env_rel_set_alloc_Constr; [| eapply Halloc1 | eapply Halloc2 | ].

          intros j1. 
          eapply env_log_rel_i_monotonic with (i := k); tci. 
          
          eapply env_log_rel_P_antimon.  
          eapply Hrel.

          normalize_occurs_free. rewrite !Setminus_Union_distr, !Setminus_Union.
          eapply Included_Union_preserv_r... 
          omega.
          eassumption.
        * eapply closed_set_alloc; [| eassumption ].
          eapply closed_reach_monotonic. eassumption.  
          normalize_occurs_free. rewrite env_locs_Union...
        * eapply drop_invariant_extend; [|eassumption]. 
          intros Hcontra. eapply Hdis1. 
          normalize_bound_var. split. eassumption. eauto with Ensembles_DB.
        * eapply binding_in_map_antimon; [| eapply binding_in_map_set; eassumption ].
          normalize_occurs_free. 
          rewrite <- Union_assoc. 
          rewrite <- (Union_Setminus (occurs_free e) [set x])...
        * inv Hun. eassumption. 
        * eapply Disjoint_Included_r; [|eassumption]. 
          normalize_bound_var... 
        * eapply Disjoint_Included_l. 
          eapply occurs_free_Econstr_Included. 
          eapply Union_Disjoint_l. 
          eapply Disjoint_Included_r; [|eassumption]. 
          normalize_bound_var... 
          inv Hun. eapply Disjoint_Singleton_l. eassumption. 
        * eassumption. 
    - (* ----------- Eprim ----------- *)
      eapply exp_rel_prim_compat. eassumption. (* XXX Zoe remove redundant argument from compat lemma *)
    - (* ----------- Eproj ----------- (1) *)
      eapply exp_rel_proj_compat.
      + eapply InvCtx.
      + eapply IInvCtx.
      + eapply InvBase.
      + intros j'. setoid_rewrite Setminus_Union in Hrel.
        eapply Hrel. 
        split; [| eassumption ].
        normalize_occurs_free...
      + intros v1 v2 Hleq Hv1 Hv2 Hrelv j'. 
        eapply IHk with (S := S) (drop := drop). 
        * simpl in *. omega. 
        * intros j''. 
          eapply env_log_rel_P_set. 

          eapply env_log_rel_i_monotonic with (i := k); tci. 
          (* Note: These generates a bunch of goals of the form [Proper ... ]. Should be solvable
             with the tactic [tci] (shorthand for [eauto with typeclass_instances]. *)
          eapply env_log_rel_P_antimon. eapply Hrel. 
          
          normalize_occurs_free. 
          rewrite !Setminus_Union.
          rewrite !Union_assoc. rewrite (Union_commut _ ([set x])).
          rewrite <- Setminus_Union...
          omega. 

          eapply Hrelv.
        * rewrite reach'_idempotent in Hclos. eapply closed_reach_monotonic. eassumption.
          eapply Included_trans. eapply env_locs_set_Inlcuded'.
          normalize_occurs_free. rewrite env_locs_Union, reach'_Union.
          eapply Included_Union_compat. eassumption.
          eapply reach'_extensive. 
        * eapply drop_invariant_extend; [| eassumption ].
          intros Hcontra.
          eapply Hdis1. 
          normalize_bound_var. split. eassumption. eauto with Ensembles_DB. 
        * eapply binding_in_map_antimon; [ | eapply binding_in_map_set; eassumption]. 
          normalize_occurs_free. 
          rewrite <- Union_assoc. 
          rewrite <- (Union_Setminus (occurs_free e) [set x])... 
        * inv Hun. eassumption.
        * eapply Disjoint_Included_r; [| eassumption ].
          normalize_bound_var...
        * eapply Disjoint_Included_l.
          eapply occurs_free_Eproj_Included.
          eapply Union_Disjoint_l.

          eapply Disjoint_Included_r; [| eassumption ].
          normalize_bound_var...

          inv Hun. eapply Disjoint_Singleton_l. eassumption.
        * eassumption. 
    - (* ----------- Ecase ----------- *)
      eapply exp_rel_case_compat.
      + eapply InvBase.
      + admit.
      + admit. 
      + setoid_rewrite Setminus_Union in Hrel. 
        eapply Hrel. constructor; eauto.
      + eapply Forall2_monotonic_strong; [| eassumption ].
        intros [t1 e1] [t2 e2] Hin1 Hin2 [Hteq Hdrop]. simpl in Hteq, Hdrop.
        split. eassumption.
        intros Hleq.
        eapply IHk; [| | | | | | | | eassumption ].
        * simpl in *. omega. 
        * intros j''.  
          eapply env_log_rel_i_monotonic with (i := k); tci. 
          eapply env_log_rel_P_antimon. eapply Hrel. 

          eapply Included_Setminus_compat. 
          eapply Included_Setminus_compat. 
          eapply occurs_free_Ecase_Included. eassumption. 
          eapply Included_refl. 
          eapply Included_refl. 
      
          simpl in *. omega. 
        * eapply closed_reach_monotonic. eassumption.
          eapply env_locs_monotonic.
          eapply occurs_free_Ecase_Included. eassumption. 
        * eassumption.
        * eapply binding_in_map_antimon; [|eassumption]. 
          eapply occurs_free_Ecase_Included. eassumption. 
        * eapply unique_bindings_Ecase_In. eassumption. eassumption.
        * eapply Disjoint_Included_r; [| eassumption ].
          intros y Hin. econstructor; eassumption.
        * eapply Disjoint_Included; [| | eapply Hdis2 ] . 
          intros y Hin. econstructor; eassumption.
          eapply occurs_free_Ecase_Included. eassumption. 
    - (* ----------- Ehalt ----------- (2) *)
      eapply exp_rel_halt_compat. 
      + eapply InvBase.
      + setoid_rewrite Setminus_Union in Hrel.
        eapply Hrel. 
        split; [| eassumption ]. 
        rewrite occurs_free_Ehalt... 
    - (* ----------- Eapp (unknown) ----------- *)
      eapply exp_rel_app_compat.  
      + admit. 
      + eapply InvBase.
      + intros j'. setoid_rewrite Setminus_Union in Hrel. 
        eapply Hrel.
        split; [|eassumption]. 
        normalize_occurs_free... 
      + eapply Forall2_forall. tci. 
        intros j'. setoid_rewrite Setminus_Union in Hrel. 
        eapply var_log_rel_Forall2.   
        * eapply Hrel.
        * normalize_occurs_free. eapply Included_Setminus.
          eassumption.
          now eauto with Ensembles_DB.
    - (* ----------- Eapp (known) ----------- *)
      eapply exp_rel_app_compat_known.
      + eassumption. (* XXX Zoe remove arg *)
      + admit. (* XXX update lemma *)
      + admit.
      + intros i rho1' B1 f1' e1 ys1 vs1 Hlt Hgetf1 Hfind1 Hgetys1 Hset1.
        
        edestruct Hdinv
          as (B1' & B2' & Hun' & Hclo' & Hdrop' & Hdom & Hyp).
        edestruct Hyp as [Hget1 Hget2]. eassumption.
        repeat subst_exp.
      
        edestruct Drop_fundefs_fun_in_fundef as
            [bs' [S' [xs2' [e2 [Hfind2 [Hdrop2 [Hparam2 Hdbody]]]]]]].
        eassumption. eassumption. repeat subst_exp. 

        edestruct env_rel_add_args_dropped as [vs2 [Hgetvs2 Hall]];
          [| eassumption | eassumption | ].
        
        * intros j'. eapply env_log_rel_P_antimon. eapply Hrel.
          normalize_occurs_free. 
          rewrite Setminus_Union. 
          eapply Included_Setminus_compat. 
          eapply Included_Union_l. reflexivity. 

        * edestruct env_rel_set_params_dropped as [rho2' [Hset2 Henv]]; 
            [ | eassumption | eassumption | eassumption | ].
          
          eapply dead_param_elim_fundefs_correct with
              (P := occurs_free e1 \\ S').
          eassumption.
          admit. (* TODO Zoe *) 
          eassumption.
          eassumption.
          unfold closed_fundefs in Hclo'. rewrite Hclo'...
          eassumption.
          eassumption. 
          eassumption. 

          do 6 eexists. repeat split; eauto. 
          
          admit. (* TODO Zoe *)
          { intros j'. eapply IHk; [| | | | | | |  | eassumption ].
            - omega. 
            - intros j''. eapply env_log_rel_P_antimon.
              eapply env_log_rel_i_monotonic with (i := k); tci. eapply Henv.  
              omega.
              
              do 2 rewrite Setminus_Union at 1.
              rewrite Setminus_Union_distr. 
              eapply Included_Union_preserv_l.
              rewrite Setminus_Union at 1.
              eapply Included_Setminus_compat. 
              reflexivity.
              now eauto with Ensembles_DB.
              
            - eapply closed_reach_monotonic. eassumption.
              eapply Included_trans.
              eapply Included_trans;
                [| eapply env_locs_setlist_Included; try now eapply Hset1 ].
              eapply env_locs_monotonic. eapply Included_Union_preserv_l. reflexivity.
              normalize_occurs_free. rewrite env_locs_Union, env_locs_FromList, env_locs_Singleton; eauto.
              rewrite Union_commut. eapply Included_Union_compat. reflexivity.
              simpl. eapply Included_trans. eapply env_locs_def_funs'; tci.
              rewrite env_locs_Empty. reflexivity.
            - admit. (* TODO zoe -- Drop_inv after setlist *)
            - (* TODO Katja -- binding in map *) admit.
            - eapply unique_bindings_fun_in_fundefs.
              eapply find_def_correct. eassumption.
              eassumption.
            - (* TODO zoe remove *) admit.
            - (* TODO Katja *) admit.
  Admitted. 
  
End DeadParamCorrect.