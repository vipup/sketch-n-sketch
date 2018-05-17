module LangParserUtils exposing
  ( space
  , spaces
  , oldSpaces
  , spacesCustom
  , nospace
  , keywordWithSpace
  , symbolWithSpace
  , spaceSaverKeyword
  , paddedBefore
  , transferInfo
  , unwrapInfo
  , isSpace
  , isOnlySpaces
  , mapPat_
  , mapWSPat_
  , mapExp_
  , mapWSExp_
  , SpacePolicy
  , spacesWithoutIndentation
  , spacesNotBetweenDefs
  , spacesWithoutNewline
  , explodeStyleValue
  , implodeStyleValue
  )

import Parser exposing (..)
import Parser.LowLevel as LL
import Parser.LanguageKit as LK

import ParserUtils exposing (..)

import Lang exposing (..)
import Info exposing (..)
import Regex
import ImpureGoodies

--------------------------------------------------------------------------------
-- Whitespace
--------------------------------------------------------------------------------

isSpace : Char -> Bool
isSpace c =
  c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\xa0'

isOnlySpaces : String -> Bool
isOnlySpaces =
  String.all isSpace

space : Parser WS
space =
  trackInfo <|
    keep (Exactly 1) isSpace

type alias SpaceParserState = { forwhat: String, withNewline: Bool, minIndentation: Maybe Int, maxIndentation: Maybe Int  }

spacesCustom: SpaceParserState -> Parser WS
spacesCustom ({forwhat, withNewline, minIndentation, maxIndentation} as options) =
  spaces |>
  map (\ws ->
    let testMinIndentation continue =
      case minIndentation of
         Just x -> if ws.end.col - 1 < x then fail <| "I need an indentation of at least " ++ toString x ++ " spaces " ++ forwhat
           else continue ()
         Nothing -> continue ()
    in
    let testMaxIndentation continue =
      case maxIndentation of
         Just x -> if ws.end.col - 1 > x then fail <| "I need an indentation of at most " ++ toString x ++ " spaces " ++ forwhat
           else continue ()
         Nothing -> continue ()
    in
    let testNewline continue =
      if withNewline then continue ()
      else if ws.start.line < ws.end.line then -- There might be comments, but For now, we just ignore them.
         fail <| "No newline allowed " ++ forwhat
      else continue ()
    in
    testMinIndentation <| \() ->
    testMaxIndentation <| \() ->
    testNewline <| \() ->
    succeed ws
  ) |>
  andThen identity

spacesRaw: Parser ()
spacesRaw =
  ignore zeroOrMore isSpace |>
    andThen (\_ ->
      oneOf [
        lineComment |> andThen (\_ -> spacesRaw),
        nestableComment "{-" "-}" |> andThen (\_ -> spacesRaw),
        succeed ()
      ])

spaces : Parser WS
spaces = trackInfo <| source <| spacesRaw

spacesWithoutIndentation: Parser WS
spacesWithoutIndentation = spacesCustom {forwhat = "at this place", withNewline=True, minIndentation=Nothing, maxIndentation=Just 0}

spacesNotBetweenDefs: Parser WS
spacesNotBetweenDefs =  spacesCustom {forwhat = "at this place", withNewline=True, minIndentation=Just 1, maxIndentation=Nothing}

spacesWithoutNewline: Parser WS
spacesWithoutNewline = spacesCustom {forwhat = "at this place", withNewline=False, minIndentation=Nothing, maxIndentation=Nothing}

lineComment: Parser ()
lineComment =
  (symbol "--"
   |. ignore zeroOrMore (\c -> c /= '\n')
   |. oneOf [ symbol "\n", end ])

nestableIgnore : Parser ignore -> Parser keep -> Parser keep
nestableIgnore ignoreParser keepParser =
  map2 (\a b -> b) ignoreParser keepParser

nestableComment : String -> String -> Parser ()
nestableComment start end =
  case (String.uncons start, String.uncons end) of
    (Nothing, _) ->
      fail "Trying to parse a multi-line comment, but the start token cannot be the empty string!"

    (_, Nothing) ->
      fail "Trying to parse a multi-line comment, but the end token cannot be the empty string!"

    ( Just (startChar, _), Just (endChar, _) ) ->
      let
        isNotRelevant char =
          char /= startChar && char /= endChar
      in
        symbol start
          |. nestableCommentHelp isNotRelevant start end 1


nestableCommentHelp : (Char -> Bool) -> String -> String -> Int -> Parser ()
nestableCommentHelp isNotRelevant start end nestLevel =
  lazy <| \_ ->
    nestableIgnore (Parser.ignore zeroOrMore isNotRelevant) <|
      oneOf
        [ nestableIgnore (symbol end) <|
            if nestLevel == 1 then
              succeed ()
            else
              nestableCommentHelp isNotRelevant start end (nestLevel - 1)
        , nestableIgnore (symbol start) <|
            nestableCommentHelp isNotRelevant start end (nestLevel + 1)
        , nestableIgnore (Parser.ignore (Exactly 1) (\_ -> True)) <|
            nestableCommentHelp isNotRelevant start end nestLevel
        ]

-- For compatibility with FastParser
oldSpacesRaw: Parser ()
oldSpacesRaw =
  ignore zeroOrMore isSpace |>
    andThen (\_ ->
      oneOf [
        oldLineComment |> andThen (\_ -> oldSpacesRaw),
        succeed ()
      ])

oldSpaces : Parser WS
oldSpaces = trackInfo <| source <| oldSpacesRaw
oldLineComment: Parser ()
oldLineComment =
  (symbol ";"
   |. ignore zeroOrMore (\c -> c /= '\n')
   |. oneOf [ symbol "\n", end ])


nospace : Parser WS
nospace =
  trackInfo <| succeed ""

guardSpace : ParserI ()
guardSpace =
  trackInfo
    ( ( succeed (,)
        |= LL.getOffset
        |= LL.getSource
      )
      |> andThen
      ( \(offset, source) ->
          guard "expecting space" <|
            isOnlySpaces <| String.slice offset (offset + 1) source
      )
    )

keywordWithSpace : String -> ParserI ()
keywordWithSpace kword =
  trackInfo <|
    succeed ()
      |. keyword kword
      |. guardSpace

symbolWithSpace : String -> ParserI ()
symbolWithSpace sym =
  trackInfo <|
    succeed ()
      |. symbol sym
      |. guardSpace

spaceSaverKeyword : Parser WS -> String -> (WS -> a) -> ParserI a
spaceSaverKeyword sp kword combiner =
  delayedCommitMap
    ( \ws _ ->
        withInfo (combiner ws) ws.start ws.end
    )
    ( sp )
    ( keyword kword )


paddedBefore : (WS -> a -> b) -> Parser WS -> ParserI a -> ParserI b
paddedBefore combiner sp p =
  delayedCommitMap
    ( \wsBefore x ->
        withInfo (combiner wsBefore x.val) x.start x.end
    )
    sp
    p

transferInfo : (a -> b) -> ParserI a -> ParserI b
transferInfo combiner p =
  map ( \x -> withInfo (combiner x.val) x.start x.end) p

unwrapInfo: ParserI (a -> b) -> Parser (a -> WithInfo b)
unwrapInfo = map (\{val, start, end} -> \a -> withInfo (val a) start end)

--------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------

mapPat_ : ParserI Pat__ -> Parser Pat
mapPat_ = (map << mapInfo) pat_

mapWSPat_ : ParserI (WS -> Pat__) -> Parser (WS -> Pat)
mapWSPat_ = (map << mapInfoWS) pat_


--------------------------------------------------------------------------------
-- Expressions
--------------------------------------------------------------------------------

mapExp_ : ParserI Exp__ -> Parser Exp
mapExp_ = (map << mapInfo) exp_

mapWSExp_ : ParserI (WS -> Exp__) -> Parser (WS -> Exp)
mapWSExp_ = (map << mapInfoWS) exp_

-- This is useful to get rid of semicolon or colons in the top-level language.
-- app   how spaces before applications argument can be parsed (e.g. if they can go one line)
-- any   how any other top-level space is parsed (e.g.
type alias SpacePolicy = { first: Parser WS, apparg: Parser WS }
-- Expressions at top-level cannot consume a newline that is followed by an identifier, or two newlines except if they are parsed inside parentheses.

styleSplitRegex = Regex.regex "(?=;\\s*\\S)"

-- Returns a complete split of the style (pre-name, name, colon, value, post-name)
explodeStyleValue: String -> List (String, String, String, String, String)
explodeStyleValue content =
  Regex.split Regex.All styleSplitRegex content
    |> List.filterMap (\s ->
         case Regex.find (Regex.AtMost 1) (Regex.regex "^(;?)([\\s\\S]*)(:)([\\s\\S]*)(;?\\s*)$") s of
           [m] -> case m.submatches of
             [Just prename, Just name, Just colon, Just value, Just postvalue] -> Just (prename, name, colon, value, postvalue)
             _ ->Nothing
           _ ->Nothing
       )

implodeStyleValue: List (String, String) -> String
implodeStyleValue content =
  content |> List.map (\(name, value) -> name ++ ":" ++ value) |> String.join ";"

