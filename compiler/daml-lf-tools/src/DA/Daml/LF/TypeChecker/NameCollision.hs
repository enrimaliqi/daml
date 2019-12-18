-- Copyright (c) 2019 The DAML Authors. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0

module DA.Daml.LF.TypeChecker.NameCollision
    ( runCheckModuleDeps
    , runCheckPackage
    ) where

import DA.Daml.LF.Ast
import DA.Daml.LF.TypeChecker.Error
import Data.Maybe
import Control.Monad.Extra
import qualified Data.NameMap as NM
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Control.Monad.State.Strict as S
import Control.Monad.Except (throwError)

-- | The various names we wish to track within a package.
-- This type separates all the different kinds of names
-- out nicely, and preserves case sensitivity, so the
-- names are easy to display in error messages. To get
-- the corresponding case insensitive fully resolved name,
-- see 'FRName'.
data Name
    = NModule ModuleName
    | NRecordType ModuleName TypeConName
    | NVariantType ModuleName TypeConName
    | NEnumType ModuleName TypeConName
    | NTypeSynonym ModuleName TypeConName
    | NVariantCon ModuleName TypeConName VariantConName
    | NEnumCon ModuleName TypeConName VariantConName
    | NField ModuleName TypeConName FieldName
    | NChoice ModuleName TypeConName ChoiceName

-- | Display a name in a super unambiguous way.
displayName :: Name -> T.Text
displayName = \case
    NModule (ModuleName m) ->
        T.concat ["module ", dot m]
    NRecordType (ModuleName m) (TypeConName t) ->
        T.concat ["record ", dot m, ":", dot t]
    NVariantType (ModuleName m) (TypeConName t) ->
        T.concat ["variant ", dot m, ":", dot t]
    NEnumType (ModuleName m) (TypeConName t) ->
        T.concat ["enum ", dot m, ":", dot t]
    NTypeSynonym (ModuleName m) (TypeConName t) ->
        T.concat ["synonym ", dot m, ":", dot t]
    NVariantCon (ModuleName m) (TypeConName t) (VariantConName v) ->
        T.concat ["variant constructor ", dot m, ":", dot t, ".", v]
    NEnumCon (ModuleName m) (TypeConName t) (VariantConName v) ->
        T.concat ["enum constructor ", dot m, ":", dot t, ".", v]
    NField (ModuleName m) (TypeConName t) (FieldName f) ->
        T.concat ["field ", dot m, ":", dot t, ".", f]
    NChoice (ModuleName m) (TypeConName t) (ChoiceName c) ->
        T.concat ["choice ", dot m, ":", dot t, ".", c]
  where
    dot = T.intercalate "."

-- | Asks whether a name collision is permitted. According to the
-- LF Spec, a name collision is only permitted when it occurs
-- between a record type and a variant constructor defined in
-- the same module.
nameCollisionPermitted :: Name -> Name -> Bool
nameCollisionPermitted a b =
    case (a,b) of
        (NRecordType m1 _, NVariantCon m2 _ _) -> m1 == m2
        (NVariantCon m1 _ _, NRecordType m2 _) -> m1 == m2
        _ -> False

-- | Asks whether a name collision is forbidden.
nameCollisionForbidden :: Name -> Name -> Bool
nameCollisionForbidden a b = not (nameCollisionPermitted a b)

-- | Fully resolved name within a package. We don't use
-- Qualified from DA.Daml.LF.Ast because that hides collisions
-- between module names and type names. This should only be
-- constructed lower case in order to have case-insensitivity.
--
-- This corresponds to the following section of the LF spec:
-- https://github.com/digital-asset/daml/blob/master/daml-lf/spec/daml-lf-1.rst#fully-resolved-name
newtype FRName = FRName [T.Text]
    deriving (Eq, Ord)

-- | Turn a name into a fully resolved name.
fullyResolve :: Name -> FRName
fullyResolve = FRName . map T.toLower . \case
    NModule (ModuleName m) ->
        m
    NRecordType (ModuleName m) (TypeConName t) ->
        m ++ t
    NVariantType (ModuleName m) (TypeConName t) ->
        m ++ t
    NEnumType (ModuleName m) (TypeConName t) ->
        m ++ t
    NTypeSynonym (ModuleName m) (TypeConName t) ->
        m ++ t
    NVariantCon (ModuleName m) (TypeConName t) (VariantConName v) ->
        m ++ t ++ [v]
    NEnumCon (ModuleName m) (TypeConName t) (VariantConName v) ->
        m ++ t ++ [v]
    NField (ModuleName m) (TypeConName t) (FieldName f) ->
        m ++ t ++ [f]
    NChoice (ModuleName m) (TypeConName t) (ChoiceName c) ->
        m ++ t ++ [c]

-- | State of the name collision checker. This is a
-- map from fully resolved names within a package to their
-- original names. We update this map as we go along.
newtype NCState = NCState (M.Map FRName [Name])

-- | Initial name collision checker state.
initialState :: NCState
initialState = NCState M.empty

-- | Monad in which to run the name collision check.
type NCMonad t = S.StateT NCState (Either Error) t

-- | Run the name collision with a blank initial state.
runNameCollision :: NCMonad t -> Either Error t
runNameCollision = flip S.evalStateT initialState

-- | Try to add a name to the NCState. Returns Error only
-- if the name results in a forbidden name collision.
addName :: Name -> NCState -> Either Error NCState
addName name (NCState nameMap) = do
    let frName = fullyResolve name
        oldNames = fromMaybe [] (M.lookup frName nameMap)
        badNames = filter (nameCollisionForbidden name) oldNames
    if null badNames then do
        Right . NCState $ M.insert frName (name : oldNames) nameMap
    else do
        Left $ EForbiddenNameCollision
            (displayName name)
            (map displayName badNames)

checkName :: Name -> NCMonad ()
checkName name = do
    oldState <- S.get
    case addName name oldState of
        Left err ->
            throwError err
        Right !newState ->
            S.put newState

checkDataType :: ModuleName -> DefDataType -> NCMonad ()
checkDataType moduleName DefDataType{..} =
    case dataCons of
        DataRecord fields -> do
            checkName (NRecordType moduleName dataTypeCon)
            forM_ fields $ \(fieldName, _) -> do
                checkName (NField moduleName dataTypeCon fieldName)

        DataVariant constrs -> do
            checkName (NVariantType moduleName dataTypeCon)
            forM_ constrs $ \(vconName, _) -> do
                checkName (NVariantCon moduleName dataTypeCon vconName)

        DataEnum constrs -> do
            checkName (NEnumType moduleName dataTypeCon)
            forM_ constrs $ \vconName -> do
                checkName (NEnumCon moduleName dataTypeCon vconName)

checkTemplate :: ModuleName -> Template -> NCMonad ()
checkTemplate moduleName Template{..} = do
    forM_ tplChoices $ \TemplateChoice{..} ->
        checkName (NChoice moduleName tplTypeCon chcName)

checkModuleName :: Module -> NCMonad ()
checkModuleName m =
    checkName (NModule (moduleName m))

checkModuleBody :: Module -> NCMonad ()
checkModuleBody m = do
    forM_ (moduleDataTypes m) $ \dataType ->
        checkDataType (moduleName m) dataType
    forM_ (moduleTemplates m) $ \tpl ->
        checkTemplate (moduleName m) tpl

checkModule :: Module -> NCMonad ()
checkModule m = do
    checkModuleName m
    checkModuleBody m

-- | Is one module an ascendant of another? For instance
-- module "A" is an ascendant of module "A.B" and "A.B.C".
--
-- Normally we wouldn't care about this in DAML, because
-- the name of a module has no relation to its logical
-- dependency structure. But since we're compiling to LF,
-- module names (e.g. "A.B") may conflict with type names
-- ("A:B"), so we need to check modules in which this conflict
-- may arise.
--
-- The check here is case-insensitive because the name-collision
-- condition in DAML-LF is case-insensitiv (in order to make
-- codegen easier for languages that control case differently
-- from DAML).
isAscendant :: ModuleName -> ModuleName -> Bool
isAscendant (ModuleName xs) (ModuleName ys) =
    (length xs < length ys) && and (zipWith sameish xs ys)
    where sameish a b = T.toLower a == T.toLower b


-- | Check whether a module and its dependencies satisfy the
-- name collision condition.
checkModuleDeps :: World -> Module -> NCMonad ()
checkModuleDeps world mod0 = do
    -- TODO #3616:  check for collisions with TypeSynonyms
    let package = getWorldSelf world
        modules = NM.toList (packageModules package)
        name0 = moduleName mod0
        ascendants = filter (flip isAscendant name0 . moduleName) modules
        descendants = filter (isAscendant name0 . moduleName) modules
    mapM_ checkModuleBody ascendants -- only need type names
    mapM_ checkModuleName descendants -- only need module names
    checkModule mod0

-- | Check a whole package for name collisions. This is used
-- when building a DAR, which may include modules in conflict
-- that don't depend on each other.
checkPackage :: Package -> NCMonad ()
checkPackage = mapM_ checkModule . packageModules

runCheckModuleDeps :: World -> Module -> Either Error ()
runCheckModuleDeps w m = runNameCollision (checkModuleDeps w m)

runCheckPackage :: Package -> Either Error ()
runCheckPackage = runNameCollision . checkPackage
