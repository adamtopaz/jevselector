import JevSelector
import CatalogFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions

run_cmd liftTermElabM do
  let some indexPath ← IO.getEnv "JEVSELECTOR_TEST_CATALOG" | throwError "missing catalog"
  let some modelPath ← IO.getEnv "JEVSELECTOR_TEST_CATALOG_DEPS" | throwError "missing dependencies"
  let idx ← load indexPath
  let model ← loadDependencies idx modelPath
  model.validateEnvironment
  discard <| model.validateHoldouts #[`CatalogFixture.held, `CatalogFixture.definitionProof]
  unless idx.artifact.publicConstants && model.artifact.publicLabels do
    throwError "explicit public catalog/label policies were lost"
  unless idx.artifact.candidateOnly.contains "CatalogFixture.identity" &&
      idx.artifact.candidateOnly.contains "CatalogFixture.definitionProof" &&
      !idx.eligibleNames.contains "CatalogFixture.definitionProof" do
    throwError "public definitions became fitted examples instead of candidates"
  unless model.examples.size == idx.eligibleNames.size &&
      model.examples.contains ``CatalogFixture.useDefinition &&
      !model.examples.contains ``CatalogFixture.definitionProof &&
      !model.examples.contains ``CatalogFixture.held do
    throwError "proof training owner set was broadened beyond eligible theorems"
  unless model.examples.getD ``CatalogFixture.useDefinition #[] == #[``CatalogFixture.definitionProof] do
    throwError "direct public definition label was not extracted"
  if model.premises.contains ``Nat.zero_add then
    throwError "extractor opened a referenced definition body or the excluded proof"
  let goal ← mkFreshExprMVar (← inferType (mkConst ``CatalogFixture.useDefinition))
  let result ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``CatalogFixture.definitionProof), maxSuggestions := 1 }
  unless result.map (·.name) == #[``CatalogFixture.definitionProof] do
    throwError "expanded catalog failed to retrieve an imported definition"
  let transferred ← model.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``CatalogFixture.definitionProof), maxSuggestions := 1 }
  unless transferred.map (·.name) == #[``CatalogFixture.definitionProof] do
    throwError "proof transfer failed to retrieve its direct definition label"
  let box ← mkFreshExprMVar (mkConst ``CatalogFixture.Box)
  let constructor ← idx.selector {} box.mvarId! {
    filter := fun n => pure (n == ``CatalogFixture.Box.mk), maxSuggestions := 1 }
  unless constructor.map (·.name) == #[``CatalogFixture.Box.mk] do
    throwError "expanded catalog did not retrieve a public constructor"
  let poisoned := { idx.artifact with
    eligible := idx.artifact.eligible.push "CatalogFixture.definitionProof" }
  let path := indexPath ++ ".poisoned"
  IO.FS.writeFile path (toJson poisoned).compress
  let rejected ← try
    discard <| load path
    pure false
  catch _ => pure true
  IO.FS.removeFile path
  unless rejected do throwError "candidate-only/fitted example overlap was accepted"

def newlyDefined : 1 = 1 := rfl

run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_TEST_CATALOG" | throwError "missing catalog"
  let idx ← load path
  let goal ← mkFreshExprMVar (← inferType (mkConst ``newlyDefined))
  let result ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``newlyDefined), maxSuggestions := 1 }
  unless result.map (·.name) == #[``newlyDefined] do
    throwError "public catalog did not supplement an earlier current-file definition"
