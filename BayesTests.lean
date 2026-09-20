import JevSelector.Bayes
import SelectorFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions

structure BayesExpectedScore where
  name : String
  score : Float
  deriving FromJson
structure BayesExpectedQuery where
  features : Array String
  scores : Array BayesExpectedScore
  deriving FromJson

run_cmd liftTermElabM do
  let some indexPath ← IO.getEnv "JEVSELECTOR_TEST_INDEX" | throwError "missing test index"
  let some modelPath ← IO.getEnv "JEVSELECTOR_TEST_BAYES" | throwError "missing Bayes model"
  let some referencePath ← IO.getEnv "JEVSELECTOR_TEST_BAYES_REFERENCE" | throwError "missing direct reference"
  let idx ← load indexPath
  let model ← loadBayes idx modelPath
  model.validateEnvironment
  discard <| model.validateHoldouts #[`SelectorFixture.held]
  if model.header.signaturePriorOwners.contains "SelectorFixture.held" ||
      model.header.signaturePriorOwners.contains "SelectorFixture.held.helper" then
    throwError "excluded statement entered a signature prior"
  let overlap ← try
    discard <| model.validateHoldouts #[`SelectorFixture.keep]
    pure false
  catch _ => pure true
  unless overlap do throwError "Bayes accepted training/evaluation overlap"
  let reference : Array BayesExpectedQuery ← IO.ofExcept
    (Json.parse (← IO.FS.readFile referencePath) >>= fromJson?)
  for query in reference do
    let ranked := model.rankFeatures query.features { maxPostingsPerSymbol := 0 }
    unless ranked.size == query.scores.size do throwError "Bayes dropped an unmatched label prior"
    -- Compare each label independently: numerical roundoff in a direct formula
    -- may differ at the last bit for mathematically tied labels.
    for expected in query.scores do
      let some (_, actual) := ranked.find? (fun (i, _) => model.premises[i]!.text == expected.name)
        | throwError "missing reference premise"
      if Float.abs (actual - expected.score) > 0.000000001 then
        throwError "native Bayes differs from direct formula: {expected.name}"
    unless ranked.map (fun (i, _) => model.premises[i]!.text) ==
        (model.rankFeatures (query.features ++ query.features) { maxPostingsPerSymbol := 0 }).map
          (fun (i, _) => model.premises[i]!.text) do
      throwError "duplicate query features changed ranking"
  let goal ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.held))
  let selected ← model.selector {} goal.mvarId! {
    maxSuggestions := 1, filter := fun n => pure (n == ``Nat.add_zero) }
  unless selected.map (·.name) == #[``Nat.add_zero] do
    throwError "Bayes truncated before filtering the dependency label"
  unless (← model.selector {} goal.mvarId! { maxSuggestions := 0 }).isEmpty do
    throwError "Bayes ignored zero suggestions"
  unless (← model.selector {} goal.mvarId! { filter := fun _ => pure false }).isEmpty do
    throwError "Bayes ignored the caller filter"
  let trueGoal ← mkFreshExprMVar (mkConst ``True)
  discard <| model.selector {} trueGoal.mvarId! { filter := fun _ => do
    if ← trueGoal.mvarId!.isAssigned then throwError "caller filter state leaked"
    trueGoal.mvarId!.assign (mkConst ``True.intro)
    pure true }
  if ← trueGoal.mvarId!.isAssigned then throwError "Bayes changed the caller goal"
  let invalidBound ← try
    discard <| model.selector { heartbeats := 0 } goal.mvarId! {}
    pure false
  catch _ => pure true
  unless invalidBound do throwError "Bayes accepted an unbounded query"
  let unavailable := { model with premises := model.premises.map fun (p : BayesPremise) =>
    { p with name := `Unavailable.future } }
  unless (← unavailable.selector {} goal.mvarId! {}).isEmpty do
    throwError "Bayes returned an unavailable premise"
  let stale := { model with premises := model.premises.map fun (p : BayesPremise) =>
    { p with typeHash := p.typeHash + 1 } }
  let staleRejected ← try stale.validateEnvironment; pure false catch _ => pure true
  unless staleRejected do throwError "Bayes accepted a changed imported signature"

  let saved ← saveState
  let localName := `BayesFixture.transient
  let localModel := { model with
    premises := #[{
      name := localName, text := localName.toString, typeHash := (hash (mkConst ``True)).toNat }]
    priors := #[0]
    postings := model.postings.map (fun _ => #[]) }
  addDecl <| .axiomDecl { name := localName, levelParams := [], type := mkConst ``True, isUnsafe := false }
  unless (← localModel.selector {} trueGoal.mvarId! {}).map (·.name) == #[localName] do
    throwError "Bayes omitted an available current signature"
  saved.restore
  unless (← localModel.selector {} trueGoal.mvarId! {}).isEmpty do
    throwError "Bayes leaked a rolled-back declaration"
  addDecl <| .axiomDecl { name := localName, levelParams := [], type := mkConst ``False, isUnsafe := false }
  unless (← localModel.selector {} trueGoal.mvarId! {}).isEmpty do
    throwError "Bayes reused a changed current-file profile"
  saved.restore

  let asyncName := `BayesFixture.pending
  let pending ← (← getEnv).addConstAsync asyncName .thm (reportExts := false)
  pending.commitSignature { name := asyncName, levelParams := [], type := mkConst ``True }
  try
    setEnv pending.mainEnv
    let asyncModel := { localModel with premises := #[{
      name := asyncName, text := asyncName.toString, typeHash := (hash (mkConst ``True)).toNat }] }
    unless (← asyncModel.selector {} trueGoal.mvarId! {}).map (·.name) == #[asyncName] do
      throwError "Bayes omitted an unfinished theorem's available signature"
  finally
    setEnv pending.asyncEnv
    addDecl <| .thmDecl {
      name := asyncName, levelParams := [], type := mkConst ``True, value := mkConst ``True.intro }
    pending.commitCheckEnv (← getEnv)
    saved.restore

  let raw := (← IO.FS.lines modelPath)
  let records : Array BayesRecord ← raw[1:].toArray.mapM fun line =>
    IO.ofExcept (Json.parse line >>= fromJson?)
  let reject := fun (header : BayesHeader) (records : Array BayesRecord) => do
    let badPath := modelPath ++ ".invalid"
    IO.FS.writeFile badPath <| String.intercalate "\n"
      (((toJson header).compress :: records.toList.map (fun r => (toJson r).compress))) ++ "\n"
    let failed ← try discard <| loadBayes idx badPath; pure false catch _ => pure true
    IO.FS.removeFile badPath
    unless failed do throwError "Bayes accepted malformed artifact"
  reject { model.header with exampleOwners := model.header.exampleOwners.push "SelectorFixture.held" } records
  reject { model.header with signaturePriorOwners := #[] } records
  reject { model.header with signaturePriorOwners := model.header.signaturePriorOwners.push "SelectorFixture.held" } records
  reject { model.header with symbols := model.header.symbols.push "Leaked" } records
  reject { model.header with premiseCount := model.header.premiseCount + 1 } records
  reject { model.header with featureEdges := model.header.featureEdges + 1 } records
  reject { model.header with statementArtifactId := "different" } records
  reject { model.header with observedWeight := 0 } records
  reject model.header (records.push records[0]!)
  reject { model.header with premiseCount := records.size + 1 } (records.push records[0]!)
  reject model.header (records.set! 0 { records[0]! with typeHash := 2^64 })
  let some r := records.find? (fun r => !r.features.isEmpty) | throwError "missing fixture features"
  reject model.header (records.map fun p => if p.name == r.name then
    { p with features := p.features.push p.features[0]! } else p)
