const fs = require("fs")
const sns = require("sketch-n-sketch")

var source = fs.readFileSync(__dirname + "/generate.elm", "utf8");
var result = sns.objEnv.string.evaluate({v:1})(source + `

toWriteRaw |> List.map (\\(name, htmlvalue) ->
  __jsEval__ """(function() {
    const fs = require("fs");
    fs.writeFileSync(@(jsCode.stringOf(name)), '<!DOCTYPE html>\\n' + @(jsCode.stringOf(htmlvalue)), "utf8");
  })()"""
)`)

if(result.ctor == "Ok") {
  console.log("Done")
} else {
  console.log("error", result._0)
}