//////////////////////////////////////////////////////////////////////

// The padding that Ace puts on its content
var CONTENT_PADDING_LEFT = 4;

var userCoding = true;

var editor;
var markers = [];
var fontSize = 16;

var aceContent;
var aceScroller;

function initialize() {
  editor = ace.edit("editor");
  editor.$blockScrolling = Infinity;
  editor.setTheme("ace/theme/tomorrow_night");
  editor.setFontSize(fontSize);
  editor.getSession().setMode("ace/mode/elm");
  editor.setOption("dragEnabled", true); // true by default anyway
  editor.setOption("highlightActiveLine", false);
  editor.setShowPrintMargin(false);
  editor.getSession().setUseSoftTabs(true);
  editor.getSession().setTabSize(2);
  editor.setDisplayIndentGuides(false);

  editor.on("input", function() {
      var info = getEditorState();
      app.ports.receiveEditorState.send(info);
  });
  editor.selection.on("changeCursor", function() {
      var info = getEditorState();
      app.ports.receiveEditorState.send(info);
  });

  editor.getSession().on("changeScrollTop", function() {
      var info = getEditorState();
      app.ports.receiveEditorState.send(info);

  });
  editor.getSession().on("changeScrollLeft", function() {
      var info = getEditorState();
      app.ports.receiveEditorState.send(info);
  });
  editor.getSession().on("change", function() {
    if (userCoding) {
      app.ports.userHasTyped.send(null);
    }
  });

  // Ace Editor has a bug in which it does not resize when its height is changed
  // with a transition. This is kind of ugly, but it is the simplest way to
  // get around this bug and there's no real performance penalty...
  /*
  window.setInterval(function() {
    editor.resize();
    var info = getEditorState();
    app.ports.receiveEditorState.send(info);
  }, 50);
  */

  aceContent = document.getElementsByClassName("ace_content")[0];
  aceScroller = document.getElementsByClassName("ace_scroller")[0];
}


//////////////////////////////////////////////////////////////////////
// Ranges (i.e. Highlights)

var Range = ace.require('ace/range').Range

// So we can dynamically add CSS classes, which is needed to style the markers
// Generally only touches the DOM to add new ones if absolutely needed

var style = document.createElement('style');
style.id = "autogenerated_css_classes";
style.type = 'text/css';
document.getElementsByTagName('head')[0].appendChild(style);
var classDict = {};

function makeCSSClass(colorStr) {
    var autogenName = ".autogenerated_class_" + colorStr
    if (!(classDict.hasOwnProperty(autogenName))) {
        style.innerHTML = style.innerHTML
                            + ".ace_marker-layer "
                            + autogenName
                            + " { background-color : " + colorStr+ "; "
                            + "position : absolute; "
                            + "z-index : 2; "
                            + "} ";
        document.getElementById("autogenerated_css_classes").innerHTML = style.innerHTML;
        classDict[autogenName] = true;
    }
    return "autogenerated_class_" + colorStr;
}


//////////////////////////////////////////////////////////////////////
// Demo: Displaying a hover annotation (for entire line)

function setDummyAnnotations() {

  var annots = [
    { row: 0 , text: "Info!" , type: "info" }
  , { row: 1 , text: "Warning!" , type: "warning" }
  , { row: 2 , text: "Error!" , type: "error" }
  ];

  editor.getSession().setAnnotations(annots);
}


//////////////////////////////////////////////////////////////////////
// Demo: A "tooltip" provides info when hovering over the token
// starting at a given row/column
//
// clearTooltips() and addTooltip() are defined in aceTooltips.js

function setDummyTooltips() {
  var typeTooltip = new TokenTooltip(editor, getTooltipText);
  clearTooltips();
  addTooltip(0, 0, "Don't click on me, it hurts.");
  addTooltip(0, 1, "Click on me to rewrite.");
}


//////////////////////////////////////////////////////////////////////
// Display AceCodeBoxInfo from Elm

function display(info) {
  // TODO get resizing working better with dragLayoutWidget
  // editor.resize();
  // reembed(false);

  displayCode(info.code, info.oldCode);
  displayCursor(info.codeBoxInfo.cursorPos);
  // editor.selection.clearSelection(); // TODO selections
  displayMarkers(info.codeBoxInfo.highlights);
  displayAnnotations(info.codeBoxInfo.annotations);
  displayTooltips();
}

////////////////////////////////////////////////////////////////////////////////
// Display helpers

var DELETION = -1;
var EQUALITY = 0;
var INSERTION = 1;

var dmp = new diff_match_patch();
function diff(oldString, newString) {
  var diff = dmp.diff_main(oldString, newString);
  dmp.diff_cleanupSemantic(diff);
  return diff;
}

function advance(s) {
  var row = 0;
  var col = 0;
  for (var i = 0; i < s.length; i++) {
    var c = s.charAt(i);
    if (c == "\n") {
      row += 1;
      col = 0;
    } else {
      col += 1;
    }
  }
  return [row, col]
}

function clearMarkers() {
  var markers = editor.getSession().getMarkers(false);
  for (var m in markers) {
    editor.getSession().removeMarker(m);
  }
}

function displayCode(code, oldCode) {
  userCoding = false;

  clearMarkers();
  editor.getSession().setValue(code, 0);
  if (code != oldCode) {
    var codeDiff = diff(oldCode, code);
    var row = 0;
    var col = 0;
    for (var i = 0; i < codeDiff.length; i++) {
      var change = codeDiff[i];
      var kind = change[0];
      var content = change[1];

      var deltaPos = advance(content);
      var endRow = row + deltaPos[0];
      var endCol = deltaPos[0] == 0 ? col + deltaPos[1] : deltaPos[1];

      console.log(row, col);
      var kindClass = "diff-unknown"
      if (kind == DELETION) {
        kindClass = "diff-deletion";
      } else if (kind == EQUALITY) {
        kindClass = "diff-equality";
      } else if (kind == INSERTION) {
        kindClass = "diff-insertion";
      } else {
        console.log("Unknown diff kind '" + kind + "' for content '" + content +" '.");
      }

      editor.getSession().addMarker(
        new Range(row, col, endRow, endCol),
        kindClass,
        "text",
        false
      );

      row = endRow;
      col = endCol;
    }
  }

  userCoding = true;
}

function displayCursor(cursorPos) {
  editor.moveCursorTo(cursorPos.row, cursorPos.column);
}

function displayMarkers(highlights) {

  // Add the special syntax highlighting for changes and such
  // These are 'markers', see:
  // http://ace.c9.io/#nav=api&api=edit_session
  // ctl+f addMarker
  for (mi in markers) {
      editor.getSession().removeMarker(markers[mi]);
  }
  markers = [];
  for (hi in highlights) {
      hiRange = highlights[hi].range;
      var aceRange = new Range(hiRange.start.row - 1, //Indexing from 1 in Elm?
                               hiRange.start.column - 1,
                               hiRange.end.row - 1,
                               hiRange.end.column - 1);
      var hiClass = makeCSSClass(highlights[hi].color);
      var mid = editor.getSession().addMarker(aceRange,hiClass,"text", false);
      editor.resize();
      markers.push(mid);
  }
  editor.updateSelectionMarkers();
}

function displayAnnotations(annotations) {

  // setDummyAnnotations();

  editor.getSession().clearAnnotations();
  var annots = [];
  for (idx in annotations) {
      console.log("annot: " + annotations[idx].row);
      annots.push(
          { row  : annotations[idx].row
          , text : annotations[idx].text
          , type : annotations[idx].type_
          });
  }
  editor.getSession().setAnnotations(annots);
}

function displayTooltips() {
  // TODO
  // setDummyTooltips();
}


//////////////////////////////////////////////////////////////////////
// Update AceCodeBoxInfo to Send to Elm

function getEditorState() {
  var codeBoxInfo =
    { cursorPos : editor.getCursorPosition()
    , selections : editor.selection.getAllRanges()
    , highlights : [] // TODO
    , annotations : editor.getSession().getAnnotations().map(function (annot) { return { row: annot.row, text: annot.text, type_ : annot.type } })
    , tooltips : [] // TODO
    , fontSize : fontSize
    , lineHeight : editor.renderer.layerConfig.lineHeight
    , characterWidth : editor.renderer.layerConfig.characterWidth
    , offsetLeft: editor.renderer.container.offsetLeft
    , offsetHeight: editor.renderer.container.offsetTop
    , gutterWidth: editor.renderer.gutterWidth
    , firstVisibleRow: editor.renderer.getFirstVisibleRow()
    , lastVisibleRow: editor.renderer.getLastVisibleRow()
    , marginTopOffset: aceContent.offsetTop
    , marginLeftOffset: aceContent.offsetLeft
    , scrollerTop: aceScroller.getBoundingClientRect().top
    , scrollerLeft: aceScroller.getBoundingClientRect().left
    , scrollerWidth: aceScroller.getBoundingClientRect().width
    , scrollerHeight: aceScroller.getBoundingClientRect().height
    , contentLeft: CONTENT_PADDING_LEFT
    , scrollTop: editor.session.$scrollTop
    , scrollLeft : editor.session.$scrollLeft
    };
  var info =
    { code : editor.getSession().getDocument().getValue()
    , codeBoxInfo : codeBoxInfo
    , oldCode : ""
    };
  return info;
}


//////////////////////////////////////////////////////////////////////
// Ports

app.ports.aceCodeBoxCmd.subscribe(function(aceCmd) {
  var message = aceCmd.message;

  if (message == "initializeAndDisplay") {
    initialize();
    display(aceCmd.info);

  } else if (message == "display") {
    display(aceCmd.info);

  } else if (message == "resize") {
    editor.resize();
    display(aceCmd.info);

  } else if (message == "updateFontSize") {
    fontSize = aceCmd.info.codeBoxInfo.fontSize;
    editor.setFontSize(fontSize);
    display(aceCmd.info);

  } else if (message == "changeScroll") {

  } else if (message == "resetScroll") {
    editor.scrollToLine(0, true, true, function () {});
    editor.gotoLine(0, 0, true);
  } else {
    console.log("[aceCodeBox.js] unexpected message: " + message);
  }

});

app.ports.setReadOnly.subscribe(function(flag) {
  editor.setReadOnly(flag);
});

app.ports.setSelections.subscribe(function(ranges) {
  editor.clearSelection();

  var range, selection;
  var len = ranges.length;

  for (var i = 0; i < len; i++) {
    range = ranges[i];
    selection = new Range(
      range.start.row,
      range.start.column,
      range.end.row,
      range.end.column
    );
    // TODO handle multiple selection
    editor.selection.setSelectionRange(selection);
  }
});

// receiveEditorState port is in initialize()
