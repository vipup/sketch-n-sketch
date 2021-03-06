original =
  """#[Markdown](https://fr.wikipedia.org/wiki/Markdown) demo
This is *an **almost :"bidirectional":*** markdown
editor. You can **fully** edit the value of the variable `original` on the right,
and _partially_ edit the html on the right.

*Limitation*: Since this is a regex-based transformation, it cannot correctly nest italics into bold (unless you use underscores instead of stars)
#### Markdown source
* Headers of level n are prefixed with n #
* Use * or 1. to introduce lists

#### Html rendering
1. You can insert elements in lists.
2. Use SHIFT+ENTER for new lines.
3. Do not use CTRL+V

#### Anywhere
2. Add bold by wrapping with two stars.
3. Add emphasis by wrapping with underscorses.
1. Use backtick to insert `code`

>Markdown is a lightweight markup
>language with plain text formatting syntax

"""

{trim, sprintf, length} = String
{foldl = foldLeft} = List
{freeze, strDiffToConcreteDiff} = Update

trim s = case extractFirstIn "^\\s*([\\s\\S]*?)\\s*$" s of
      Just [trimmed] -> trimmed
      Nothing -> s

-- Thanks to https://gist.github.com/jbroadway/2836900
markdown text =
  let para regs =
      let line = nth regs.group 2 in
      let trimmed = trim line in
      if (matchIn "^</?(ul|ol|li|h|p|bl)" trimmed) then
        (nth regs.group 1) + line
      else
        nth regs.group 1 + "<p>" + line + "</p>\n"
  in
  let ul_list regs = 
      let item = nth regs.group 1 in
      "\n<ul>\n\t<li >" + trim item + "</li>\n</ul>"
  in
  let ol_list regs =
      let item = nth regs.group 1 in
      "\n<ol>\n\t<li >" + trim item + "</li>\n</ol>"
  in
  let blockquote regs =
      let item = nth regs.group 2 in
      "\n<blockquote>" + trim item + "</blockquote>"
  in
  let header {group= [tmp, nl, chars, header]} =
      let level = toString (length chars) in
      "<h" + level + ">" + trim header + "</h" + level + ">"
  in
  "\n" + text + "\n" |>
  replaceAllIn "(\n|^)(#+)(.*)" header |>
  replaceAllIn "\\[([^\\[]+)\\]\\(([^\\)]+)\\)" "<a href='$2'>$1</a>" |>
  replaceAllIn "(\\*\\*|__)(?=[^\\s\\*_])(.*?)\\1" "<strong>$2</strong>" |>
  replaceAllIn "(\\*|_)(?=[^\\s\\*_])(.*?)\\1" "<em>$2</em>" |>
  replaceAllIn "\\~\\~(.*?)\\~\\~" "<del>$1</del>" |>
  replaceAllIn "\\:\"(.*?)\"\\:" "<q>$1</q>" |>
  replaceAllIn "`\\b(.*?)\\b`" "<code>$1</code>" |>
  replaceAllIn "\r?\n\\*(.*)" ul_list |>
  replaceAllIn "\r?\n[0-9]+\\.(.*)" ol_list |>
  replaceAllIn "\r?\n(&gt;|\\>)(.*)" blockquote |>
  replaceAllIn "\r?\n-{5,}" "\n<hr>" |>
  replaceAllIn "\r?\n\r?\n(?!<ul>|<ol>|<p>|<blockquote>)" "<br>" |>
  replaceAllIn "\r?\n</ul>\\s?<ul>" "" |>
  replaceAllIn "\r?\n</ol>\\s?<ol>" "" |>
  replaceAllIn "</blockquote>\\s?<blockquote>" "\n"

Html.span [] [] <| html ((freeze markdown) original)