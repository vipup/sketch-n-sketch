module SleekView exposing (view)

import List
import Dict

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events as E

import Utils
import HtmlUtils exposing (handleEventAndStop)

import InterfaceModel as Model exposing
  ( Msg(..)
  , Model
  , Tool(..)
  , ShapeToolKind(..)
  , Mode(..)
  , ReplicateKind(..)
  , LambdaTool(..)
  , Caption(..)
  , MouseMode(..)
  , mkLive_
  , DialogBox(..)
  )

import InterfaceController as Controller

import SleekLayout
import Canvas

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

textButton : String -> Msg -> Html Msg
textButton text onClickHandler =
  textButtonExtra text onClickHandler False

textButtonExtra : String -> Msg -> Bool -> Html Msg
textButtonExtra text onClickHandler disabled =
  let
    disabledFlag =
      if disabled then " disabled" else ""
  in
    Html.span
      [ Attr.class <| "text-button" ++ disabledFlag
      , E.onClick onClickHandler
      ]
      [ Html.text text
      ]

--------------------------------------------------------------------------------
-- Menu Bar
--------------------------------------------------------------------------------

menuBar : Model -> Html Msg
menuBar model =
  let
    menu heading options =
      let
        activeFlag =
          if model.viewState.currentMenu == Just heading then
            " active"
          else
            ""
        menuHeading =
          Html.div
            [ Attr.class "menu-heading"
            , E.onClick (Controller.msgToggleMenu heading)
            ]
            [ Html.text heading
            ]
        menuOptions =
          let
            menuOptionDivider =
              Html.div
                [ Attr.class "menu-option-divider"
                ]
                []
          in
            Html.div
              [ Attr.class "menu-options"
              ]
              ( options
                  |> List.intersperse [ menuOptionDivider ]
                  |> List.concat
              )
      in
        Html.div
          [ Attr.class <| "menu" ++ activeFlag
          ]
          [ menuHeading
          , menuOptions
          ]
  in
    Html.div
      [ Attr.class "menu-bar"
      ]
      [ Html.div
          [ Attr.class "main-bar"
          ]
          [ Html.img
              [ Attr.class "logo-image"
              , Attr.src "img/logo.png"
              , Attr.width 20
              , Attr.height 20
              ]
              []
          , menu "File"
              [ [ textButton "New" <|
                    Controller.msgOpenDialogBox New
                , textButton "Save As" <|
                    Controller.msgOpenDialogBox SaveAs
                , textButtonExtra "Save"
                    Controller.msgSave
                    (not model.needsSave)
                ]
              , [ textButton "Open" <|
                    Controller.msgOpenDialogBox Open
                ]
              , [ textButton "Export Code"
                    Controller.msgExportCode
                , textButton "Export SVG"
                    Controller.msgExportSvg
                ]
              , [ textButton "Import Code" <|
                    Controller.msgOpenDialogBox ImportCode
                , textButton "Import SVG"
                    Controller.msgNoop
                ]
              ]
          , menu "Edit"
              [ [ Html.text "Dig Hole"
                , Html.text "Make Equal"
                , Html.text "Relate"
                , Html.text "Indexed Relate"
                ]
              , [ Html.text "Dupe"
                , Html.text "Merge"
                , Html.text "Group"
                , Html.text "Abstract"
                ]
              , [ Html.text "Repeat Right"
                , Html.text "Repeat To"
                , Html.text "Repeat Around"
                ]
              ]
          ]
      , Html.div
          [ Attr.class "quick-action-bar"
          ]
          [ Html.div
              [ Attr.class "quick-action-bar-label"
              ]
              [ Html.text "Quick Actions"
              ]
          , textButtonExtra "Save"
              Controller.msgSave
              (not model.needsSave)
          , textButton "Open" <|
              Controller.msgOpenDialogBox Open
          ]
      ]

--------------------------------------------------------------------------------
-- Code Panel
--------------------------------------------------------------------------------

codePanel : Model -> Html Msg
codePanel model =
  let
    runButton =
      Html.div
        [ Attr.class "run"
        , E.onClick Controller.msgRun
        ]
        [ Html.text "Run ▸"
        ]
    actionBar =
      Html.div
        [ Attr.class "action-bar"
        ]
        [ textButton "Undo" Controller.msgUndo
        , textButton "Redo" Controller.msgRedo
        , textButton "Clean Up" Controller.msgCleanCode
        , runButton
        ]
    editor =
      Html.div
        [ Attr.id "editor"
        ]
        []
    statusBar =
      Html.div
        [ Attr.class "status-bar"
        ]
        [ Html.text "status-bar"
        ]
  in
    Html.div
      [ Attr.class "panel code-panel"
      ]
      [ actionBar
      , editor
      , statusBar
      ]

--------------------------------------------------------------------------------
-- Resizer
--------------------------------------------------------------------------------

resizer : Model -> Html Msg
resizer model =
  Html.div
    [ Attr.class "resizer"
    ]
    []

--------------------------------------------------------------------------------
-- Output Panel
--------------------------------------------------------------------------------

textArea text attrs =
  let innerPadding = 4 in
  -- NOTE: using both Attr.value and Html.text seems to allow read/write...
  let commonAttrs =
    [ Attr.spellcheck False
    , Attr.value text
    , Attr.style
        [ ("font-family", "monospace")
        , ("font-size", "14px")
        , ("whiteSpace", "pre")
        , ("height", "100%")
        , ("resize", "none")
        , ("overflow", "auto")
        -- Horizontal Scrollbars in Chrome
        , ("word-wrap", "normal")
        -- , ("background-color", "whitesmoke")
        , ("background-color", "white")
        , ("padding", toString innerPadding ++ "px")
        -- Makes the 100% for width/height work as intended
        , ("box-sizing", "border-box")
        ]
    ]
  in
  Html.textarea (commonAttrs ++ attrs) [ Html.text text ]

pixels n = toString n ++ "px"

outputPanel : Model -> Html Msg
outputPanel model =
  let
    (width, height) =
      SleekLayout.outputPanelDimensions model
    output =
      case (model.errorBox, model.mode, model.preview) of
        (_, _, Just (_, Err errorMsg)) ->
          textArea errorMsg
            [ Attr.style [ ("width", pixels width) ] ]
        (_, _, Just (_, Ok _)) ->
          Canvas.build width height model
        (Just errorMsg, _, Nothing) ->
          textArea errorMsg
            [ Attr.style [ ("width", pixels width) ] ]
        (Nothing, Print svgCode, Nothing) ->
          textArea svgCode
            [ Attr.style [ ("width", pixels width) ] ]
        (Nothing, _, _) ->
          Canvas.build width height model
  in
    Html.div
      [ Attr.class "panel output-panel"
      ]
      [ output
      ]

--------------------------------------------------------------------------------
-- Tool Panel
--------------------------------------------------------------------------------

showRawShapeTools = False

type ButtonKind = Regular | Selected | Unselected

buttonRegularColor = "white"
buttonSelectedColor = "lightgray"

iconButton model iconName onClickHandler btnKind disabled =
  iconButtonExtraAttrs model iconName [] onClickHandler btnKind disabled

iconButtonExtraAttrs model iconName extraAttrs onClickHandler btnKind disabled =
  let
    color =
      case btnKind of
        Regular    -> buttonRegularColor
        Unselected -> buttonRegularColor
        Selected   -> buttonSelectedColor
    iconHtml =
      case Dict.get (String.toLower iconName) model.icons of
        Just h -> h
        Nothing -> Html.text ""
  in
  let commonAttrs =
    [ Attr.disabled disabled
    , Attr.style [ ("width", "40px")
                 , ("height", "40px")
                 , ("background", color)
                 , ("cursor", "pointer")
                 ]
    ]
  in
  Html.button
    (commonAttrs ++
      [ handleEventAndStop "mousedown" Controller.msgNoop
      , E.onClick onClickHandler
      , Attr.title iconName
      ] ++
      extraAttrs)
    [ iconHtml ]

toolButton model tool =
  let capStretchy s = if showRawShapeTools then "BB" else s in
  let capSticky = Utils.uniPlusMinus in -- Utils.uniDelta in
  let capRaw = "(Raw)" in
  let cap = case tool of
    Cursor        -> "Cursor"
    Line Raw      -> "Line"
    Rect Raw      -> "Rect"
    Rect Stretchy -> capStretchy "Rect" -- "Box"
    Oval Raw      -> "Ellipse"
    Oval Stretchy -> capStretchy "Ellipse" -- "Oval"
    Poly Raw      -> "Polygon"
    Poly Stretchy -> capStretchy "Polygon"
    Poly Sticky   -> capSticky
    Path Raw      -> "Path"
    Path Stretchy -> capStretchy "Path"
    Path Sticky   -> capSticky
    Text          -> "Text"
    HelperLine    -> "(Rule)"
    HelperDot     -> "(Dot)"
    Lambda _      -> "Lambda" -- Utils.uniLambda
    _             -> Debug.crash ("toolButton: " ++ toString tool)
  in
  -- TODO temporarily disabling a couple tools
  let (btnKind, disabled) =
    case (model.tool == tool, tool) of
      (True, _)            -> (Selected, False)
      (False, Path Sticky) -> (Regular, True)
      (False, _)           -> (Unselected, False)
  in
    Html.div
      [ Attr.class "tool"
      ]
      [ iconButton
          model cap (Msg cap (\m -> { m | tool = tool })) btnKind disabled
      ]

lambdaTools : Model -> List (Html Msg)
lambdaTools model =
  let buttons =
    Utils.mapi1 (\(i, lambdaTool) ->
      let
        iconName = Model.strLambdaTool lambdaTool
      in
        Html.div
          [ Attr.class "tool"
          ]
          [ iconButton model iconName
              (Msg iconName (\m -> { m | tool = Lambda i }))
              (if model.tool == Lambda i then Selected else Unselected)
              False
          ]
      ) model.lambdaTools
  in
    buttons

toolPanel : Model -> Html Msg
toolPanel model =
  Html.div
    [ Attr.class "panel tool-panel"
    ]
    ( [ toolButton model Cursor
      , toolButton model Text
      , toolButton model (Line Raw)
      , toolButton model (Rect Raw)
      , toolButton model (Oval Raw)
      , toolButton model (Poly Raw)
      , toolButton model (Path Raw)
      ] ++ (lambdaTools model)
    )

--------------------------------------------------------------------------------
-- Work Area
--------------------------------------------------------------------------------

workArea : Model -> Html Msg
workArea model =
  Html.div
    [ Attr.class "work-area"
    ]
    [ codePanel model
    , resizer model
    , outputPanel model
    , toolPanel model
    ]

--------------------------------------------------------------------------------
-- Main View
--------------------------------------------------------------------------------

view : Model -> Html Msg
view model =
  Html.div
    []
    [ menuBar model
    , workArea model
    ]
