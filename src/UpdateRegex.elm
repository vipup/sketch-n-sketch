module UpdateRegex exposing (updateRegexReplaceAllByIn, evalRegexReplaceAllByIn, allInterleavingsIn)

import UpdateStack exposing (NextAction(..), UpdateStack(..), Output)
import Results exposing
  ( Results(..)
  , ok1, oks, okLazy )
import LazyList exposing (LazyList(..))
import Lang exposing (..)
import Regex exposing (..)
import Lazy
import Utils
import ImpureGoodies
import GroupStartMap
import Syntax
import Dict
import UpdateUtils exposing (..)
import LangUtils exposing (valToString)
--import LangTools exposing (valToString)

removeSlashDollar s = replace All (regex "\\\\\\$") (\_ -> "\\$") s
addSlashDollar s = replace All (regex "\\$") (\_ -> "\\\\\\$") s

lambdaBodyToString:Exp -> String
lambdaBodyToString e =
  case e.val.e__ of
    EFun _ _ body _ -> lambdaBodyToString body
    EApp space1 _ [_, pos] _ _ -> lambdaBodyToString pos
    EConst _ groupIndex _ _  -> "$" ++ toString groupIndex
    EOp space0 _ {-ToStrExceptStr-} [a] _-> lambdaBodyToString a
    EOp space1 _ {-Plus -} [a, b] space2 -> lambdaBodyToString a ++ lambdaBodyToString b
    EParens _ e _ _ -> lambdaBodyToString e
    ESelect _ e _ _ _ -> lambdaBodyToString e
    EBase _ (EString _ s) -> addSlashDollar s
    _ -> Debug.crash "[internal error] I should not have encountered a different case for UpdateRegex.lambdaBodyToString"

lambdaToString: Val -> String
lambdaToString v =
  case v.v_ of
    VClosure Nothing [_] lambdaBody env ->
      lambdaBodyToString lambdaBody
    _ -> Debug.crash "Trying to call lambdaToString with something else than a closure"

stringToLambda: Env -> Val -> String -> Val
stringToLambda env vs s =
  let l = find All (regex "(\\\\\\$|\\$(\\d))") s |> List.map (\m -> (m, m.index, String.length m.match + m.index)) in
  let m = EVar space0 "m" in
  let lastStart = { value = 0 } in
  let tmp = List.concatMap (\(mat, start, end) ->
       let groupIndexMaybe = case mat.submatches of
         [_, Nothing] -> Nothing
         [_, Just submatch] ->
            case String.toInt submatch of
              Ok i -> Just i
              Err msg -> ImpureGoodies.throw <| EvaluationError <| mat.match ++ " is not a valid group match: " ++ msg
         _ -> ImpureGoodies.throw <| EvaluationError <| mat.match ++ " is not a valid group match"
       in
       case groupIndexMaybe of
         Nothing -> [] --It was just a regular escaped dollar
         Just groupIndex ->
           let res = [ withDummyExpInfo <| EBase space1 (EString "\"" (removeSlashDollar (String.slice lastStart.value start s))),
                        withDummyExpInfo <| ESelect space1 (withDummyExpInfo <| EParens space0 (withDummyExpInfo <|
                          EApp space1 (withDummyExpInfo <| EVar space1 "nth") [
                           withDummyExpInfo <| ESelect space0 (withDummyExpInfo m) space0 space0 "group",
                            withDummyExpInfo <| EConst space1 (toFloat groupIndex) dummyLoc noWidgetDecl] SpaceApp space0
                        ) Parens space0) space0 space0 "match"] in
           let _ = ImpureGoodies.mutateRecordField lastStart "value" end in
           res
       ) l
  in
  let lambdaBody = List.foldr (\a b ->
       case a.val.e__ of
         EBase _ (EString _ _) -> eOp Plus [a, b]
         _ -> eOp Plus [eOp ToStrExceptStr [a], b]
       ) (withDummyExpInfo <| EBase space1 (EString "\"" <| removeSlashDollar(String.dropLeft lastStart.value s))) tmp
  in replaceV_ vs <| VClosure Nothing [withDummyPatInfo <| PVar space0 "m" noWidgetDecl] lambdaBody env

type EvaluationError = EvaluationError String

matchToExpApp: Exp -> GroupStartMap.Match -> Exp
matchToExpApp replacementVar m =
  let mainMatch = eStr m.match in
  let subMatches = List.map (\{match, start} -> eStr <| Maybe.withDefault "" match) m.submatches in
  let subgroup= List.map (\{match, start} -> eRecord [("match", eStr <| Maybe.withDefault "" match), ("start", eConst (toFloat start) dummyLoc)]) m.submatches in
  let argument = eRecord [("match", mainMatch),
                   ("submatches", eList subMatches Nothing),
                   ("group",      eList ((eRecord [("match", mainMatch), ("start", eConst (toFloat m.index) dummyLoc)]) :: subgroup) Nothing),
                   ("index",      eConst (toFloat m.index) dummyLoc),
                   ("number",     eConst (toFloat m.number) dummyLoc)]
  in
  eLet [("_", argument)] <|
  (eOp ToStrExceptStr [
    eApp replacementVar [argument]])

r: String -> (a -> Maybe b) -> a -> (b -> Result String c) -> Result String c
r msg unapply e c = Result.fromMaybe msg (unapply e) |> Result.andThen c

p: String -> (b -> Maybe c) -> List b -> (List c -> Result String e) -> Result String e
p msg transformer input c = List.map transformer input |> Utils.projJusts |> Result.fromMaybe msg |> Result.andThen c

extractHeadTail: String -> List a -> ((a, List a) -> Result String e) -> Result String e
extractHeadTail msg list continuation =
   case list of
     [] -> Err msg
     head::tail -> continuation (head, tail)

-- Reverse operation of matchToExpApp
expAppToStringMatch : Exp -> Result String String {- The matched string -}
expAppToStringMatch  newE =
  let extractFive names l = case List.unzip l of
    (foundNames, [elem1, elem2, elem3, elem4, elem5]) -> if foundNames == names then Just (elem1, elem2, elem3, elem4, elem5) else Nothing
    _ -> Nothing
  in
  let extractTwo names ext1 ext2 l = case List.unzip l of
    (foundNames, [elem1, elem2]) -> if foundNames == names then
        ext1 elem1 |> Maybe.andThen (\v1 -> ext2 elem2 |> Maybe.map (\v2 -> (v1, v2)))
       else Nothing
    _ -> Nothing
  in
  let eConstIntUnapply = eConstUnapply >> Maybe.map floor in
  let extractRecord: Exp -> ((String, List String, List (String, Int), Int, Int) -> Result String e) -> Result String e
      extractRecord argument continuation =
       r "Internal error, Expected record, got something else" eRecordUnapply argument <| \recordElems ->
       r "InternalError, expected 5 elements, got something else" (extractFive ["match", "submatches", "group", "index", "number"]) recordElems <| \(oldMatch, oldSubmatches, oldGroup, oldIndex, oldNumber) ->
       r "InternalError, expected a string, got something else" eStrUnapply oldMatch <| \oldMatchString ->
       r "InternalError, expected a number, got something else" eConstIntUnapply oldIndex <| \oldIndexNum ->
       r "InternalError, expected a number, got something else" eConstIntUnapply oldNumber <| \oldNumberNum ->
       r "Internal error, expected a list of submatches" eListUnapply oldSubmatches <| \oldSubmatchesList ->
       r "Internal error, expected a list of submatches" eListUnapply oldGroup <| \oldGroupList ->
       p "Submatch is supposed to be a list of strings." eStrUnapply oldSubmatchesList <| \oldSubmachesStringList ->
       p "group is supposed to stay a list of record" eRecordUnapply oldGroupList <| \oldGroupRecordList ->
       p "Internal error, expecting {match,start} for each group" (extractTwo ["match", "start"] eStrUnapply eConstIntUnapply) oldGroupRecordList <| \oldGroupValues ->
       continuation (oldMatchString, oldSubmachesStringList, oldGroupValues, oldIndexNum, oldNumberNum)
  in

  r "Internal error, could not recover a let" eLetUnapply newE <| \((name, oldArgument), bodyExp) ->
  extractRecord oldArgument <| \(oldMatch, oldSubmatches, oldGroups, oldIndex, oldNumber) ->
  r "Internal error, expected ToStrExceptStr" (eOpUnapply1 ToStrExceptStr) bodyExp <| \theapp ->
  r "Internal error, expected Application" eAppUnapply1 theapp <| \(vfun, arg) ->
  extractRecord arg <| \(newMatch, newSubmatches, newGroups, newIndex, newNumber) ->
      -- Now we need to look for the updated match.
    if newMatch /= oldMatch then
      Ok newMatch
    else if newIndex /= oldIndex then
      Err "Cannot update the index of a matched regular expression, only the string itself !"
    else if newNumber /= oldNumber then
      Err "Cannot update the index of a matched regular expression, only the string itself !"
    else if List.length newSubmatches /= List.length oldSubmatches then
      Err "Cannot change the length of the submatches, only the strings"
    else if List.length newGroups /= List.length oldGroups then
      Err "Cannot change the length of the group list, only the strings"
    else -- Maybe a subgroup has been changed ?
     let allsubgroups = UpdateUtils.mergeList (mergeTuple mergeString mergeInt) oldGroups newGroups (Utils.zip (newMatch::newSubmatches) (List.map Tuple.second newGroups)) in
     -- We recover all changes and push only the biggest ones if there are conflicts.
     List.map2 (\(mo, so) (m2, s2) ->
       if so /= s2 then Err "Cannot change the position of a subrgoup"
       else if mo == m2 then Ok Nothing
       else Ok <| Just (so, so + String.length mo, m2)
     ) oldGroups allsubgroups
     |> Utils.projOk |> Result.map (\transformations ->
       let finalMatch = List.filterMap identity transformations |> mergeTransformations oldMatch in
       finalMatch
     )

mergeTransformations: String -> List (Int, Int, String) -> String
mergeTransformations originalString replacements =
  let aux maxReplacementIndex string transformations = case transformations of
    [] -> string
    (start, end, newGroup)::remainingTransformations ->
       if end <= maxReplacementIndex then
         let updatedString = (String.left start string) ++ newGroup ++ String.dropLeft (start + end) string in
         aux start updatedString remainingTransformations
       else
         aux maxReplacementIndex string remainingTransformations
  in aux (String.length originalString) originalString (List.sortBy (\(a, b, c) -> 0- a) replacements)



evalRegexReplaceAllByIn: Env -> (Env -> Exp -> Result String Val)-> Val -> Val -> Val -> Result String Val
evalRegexReplaceAllByIn  env eval regexpV replacementV stringV =
   case (regexpV.v_, replacementV.v_, stringV.v_) of
     (VBase (VString regexp), VBase (VString replacement), VBase (VString string)) ->
        evalRegexReplaceAllByIn env eval regexpV (stringToLambda env replacementV replacement) stringV
       -- Conver the string to a lambda with string concatenation
     (VBase (VString regexp), VClosure _ _ _ _, VBase (VString string)) ->
        ImpureGoodies.tryCatch "EvaluationError" (\() ->
          let newString = GroupStartMap.replace Regex.All regexp (\m ->
               let replacementName = "UpdateRegex.replaceAll" in
               let localExp = matchToExpApp (eVar replacementName) m in
               let localEnv = [(replacementName, replacementV)] in
               --let _ = Debug.log ("The new env is" ++ LangUtils.envToString localEnv) () in
               --let _ = Debug.log ("The replacement body is" ++ Syntax.unparser Syntax.Elm localExp) () in
               case eval localEnv localExp of
                 Err msg -> ImpureGoodies.throw (EvaluationError msg)
                 Ok v ->
                    case v.v_ of
                      VBase (VString s) -> s
                      _ -> ImpureGoodies.throw (EvaluationError "[internal error] The function ToStrExceptStr returned something else than a string")
               ) string
          in
          Ok (replaceV_ replacementV <| VBase (VString newString))
        ) (\(EvaluationError msg) -> Err msg)
     _ -> Err <| "Expected a string for the regexp, a string or a lambda returning a string for replacement, and the text to perform the replace on. "
           -- Commented out because dependency cycle
           -- "Got " ++  valToString regexpV ++ ", " ++ valToString replacementV ++ ", " ++ valToString stringV

concat: List Exp -> Exp
concat l = case l of
  [head] -> head
  head::tail -> eOp Plus [head, concat tail]
  _ -> Debug.crash "Trying to call concat with an empty list"

unconcat: Exp -> List Exp
unconcat e = case e.val.e__ of
  EOp _ p [head, tail] _ -> case p.val of
    Plus -> unconcat head ++ unconcat tail
    _ -> [e]
  _ -> [e]

-- We need the environment just to make use of the function "nth" for lists, so we don't need to return it !!
updateRegexReplaceAllByIn: Env -> (Env -> Exp -> Result String Val)-> (Env -> Exp -> Val -> Val -> Results String (Env, Exp)) -> Val -> Val -> Val -> Val -> Val -> Results String (Val, Val, Val)
updateRegexReplaceAllByIn env eval updateRoutine regexpV replacementV stringV oldOutV outV =
   case (regexpV.v_, replacementV.v_, stringV.v_, outV.v_) of
     (VBase (VString regexp), VBase (VString replacement), VBase (VString string), _) ->
        updateRegexReplaceAllByIn env eval updateRoutine regexpV (stringToLambda env replacementV replacement) stringV oldOutV outV
        |> Results.map (\(newRegexpV, newReplacementV, newStringV) ->
          (newRegexpV, replaceV_ replacementV <| VBase <| VString <| lambdaToString <| newReplacementV, newStringV)
        )
       -- Conver the string to a lambda with string concatenation
     (VBase (VString regexp), VClosure _ _ _ _ , VBase (VString string), VBase (VString out)) ->
       -- If possible, we are going to parse the result to recover each changed
       -- replaceAllIn (A|B) (case of "A" -> "a"; "B" -> "b") "A,B"  gives "a,b". What if it is now replaced by x,y ? Can we change "a" and "b" in the lambda?
       -- Now yes because we can merge all results.
       let matches = GroupStartMap.find Regex.All regexp string in
       let (lastEnd, initStrings) = List.foldl (\m (lastEnd, strings) ->
            (m.index + String.length m.match, strings ++ [String.slice lastEnd m.index string])
            ) (0, []) matches
       in
       let lastString = String.dropLeft lastEnd string in -- Of size >= 2
       let replacementName = "UpdateRegex.replaceAll" in
       let expressionReplacement = concat <| List.concatMap identity <| List.map2 (\m s -> [matchToExpApp (eVar replacementName) m, eStr s]) matches initStrings in
       case evalRegexReplaceAllByIn env eval regexpV replacementV stringV of
         Err msg -> Errs msg
         Ok olvVal ->
            let envWithReplacement= (replacementName, replacementV)::env in
            updateRoutine envWithReplacement expressionReplacement olvVal outV
            |> Results.andThen (\(newEnvWithReplacement, newExp) ->
              let stringsAndLambdas = unconcat newExp in
              stringsAndLambdas |> List.map (\e ->
                case e.val.e__ of
                  EBase _ (EString delim s) -> Ok s
                  EOp _ _ [_] _ -> expAppToStringMatch e
                  _ -> Debug.crash <| "[Internal error] Expected operator or base string, got " ++ toString e
                )
              |> Utils.projOk
              |> Results.fromResult
              |> Results.andThen (\newStrings ->
                  let (newLambda, newEnv) = case newEnvWithReplacement of
                    [] -> Debug.crash "A variable disappeared from the environment"
                    (replacementName, newReplacementV)::newEnv -> (newReplacementV, newEnv)
                  in
                  let newString = String.join "" newStrings in
                  ok1 (regexpV, newLambda, replaceV_ stringV <| VBase (VString newString))
                )
             )
     _ -> Errs <| "Expected a string for the regexp, a string or a lambda returning a string for replacement, and the text to perform the replace on, and to update from a string. "
           -- Commented out because dependency cycle
           -- "Got " ++  valToString regexpV ++ ", " ++ valToString replacementV ++ ", " ++ valToString stringV

--updateRegexReplaceFirstIn

-- We can code extractFirstIn once we have records and record pattern matching.
--updateRegexExtractFirstIn: String ->




-- Given a list of strings, computes all the possible ways they split the string.
-- Each result is a list of size (List.length separators) + 1, such that interleaving this string
-- With separators results in the original string
allInterleavingsIn: List String -> String -> LazyList (List String)
allInterleavingsIn separators string =
  if List.length separators == 0 then LazyList.Cons [string] (Lazy.lazy <| \_ -> LazyList.Nil)
  else
  let aux remainingSeparators numrepetitions = case (remainingSeparators, numrepetitions) of
    ([], []) -> "(.*?)"
    (head::tail, numRep::tailNumRep) ->
       let escapedHead = escape head in
       "(.*?" ++ String.repeat numRep ("(?:(?=" ++ escapedHead ++ ").).*?") ++ ")" ++ escapedHead ++ aux tail tailNumRep
    _ -> Debug.crash "internal error: the two lists of allinterleavings should have the same size"
  in
  let lastIndex = List.length separators - 1 in
  -- We add 1 to numReps at index index, and everything afterwards should be set to zero again.
  let next index numReps =
    case numReps of
        [] -> Debug.crash "Internal error: empty numRep"
        head::tail ->
          if index == 0 then
            (head + 1) :: List.map (\_ -> 0) tail
          else
            head :: next (index - 1) tail
  in
  let initNumRep = List.map (\_ -> 0) separators in
  let findMatchFor indexRepToModify numRep =
    let r = regex <| "^" ++ aux separators numRep ++ "$" in
    let default () =
       if indexRepToModify == 0 then LazyList.Nil
       else findMatchFor (indexRepToModify - 1) <| next (indexRepToModify - 1) numRep in
    case find (AtMost 1) r string of
       [{ match, submatches, index, number }] ->
         case Utils.projJusts submatches of
           Just m ->
             LazyList.Cons m <| Lazy.lazy <| \_ ->
             findMatchFor lastIndex <| next lastIndex numRep
           Nothing ->
             default ()
       _ -> default ()
  in
  findMatchFor (List.length separators - 1) initNumRep


