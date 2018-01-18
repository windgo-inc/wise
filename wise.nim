import macros, future
import os, osproc, re, jester, htmlgen, asyncnet, random
import strutils, streams
import tables, hashes, redis, emerald
import asyncdispatch

const WISEMajorVersion = "0"
const WISEMinorVersion = "1"
const WISEVersion = WISEMajorVersion & "." & WISEMinorVersion

let redisClient = redis.open()

#type
#  SessionData = int

#var sessionTable = initTable[string, SessionData]()

# UTILITIES

proc identString(node: NimNode): string {.compileTime.} =
  case node.kind:
    of nnkAccQuoted:
      result = $node[0]
    of nnkIdent:
      result = $node
    of nnkStrLit, nnkRStrLit:
      result = node.strVal
    of nnkPostfix:
      result = identString(node[1])
    else:
      quit "Bad token, expected identifier or string literal: " & $node.kind


proc prefixIdent(name: string, pfx: string): NimNode {.compileTime.} =
  ident(pfx & name)


macro genHtml(args: varargs[untyped]): untyped =
  let args = callsite()
  
  if args.len < 2:
    quit "Expected an argument list of length >= 1."

  let stmts = newStmtList()

  stmts.add(newLetStmt(ident"htmlStringStream", newCall(ident"newStringStream")))
  stmts.add(newLetStmt(ident"htmlGenerator", newCall(prefixIdent(identString(args[1]), "new"))))

  for i in 2..<args.len:
    if args[i].kind == nnkExprEqExpr:
      stmts.add(newAssignment(newDotExpr(ident"htmlGenerator", args[i][0]), args[i][1]))
    else:
      quit "Bad argument to HTML generator, all arguments must be assignments: " & $args[i]

  stmts.add(newCall(ident"render", ident"htmlGenerator", ident"htmlStringStream"))
  stmts.add(newDotExpr(ident"htmlStringStream", ident"data"))
  result = newBlockStmt(stmts)


# SESSION

template sessionIdKey(value: untyped): untyped =
  "wise:session_" & value


proc startSession(): string =
  let value = redisClient.incr("wise:session_counter")
  let r = !$(value.hash)
  result = $r
  redisClient.setk(sessionIdKey(result), $value)


template getSession(): untyped =
  block:
    var session_hash: string
    var session_id: int
    var session_new: bool = true
    try:
      session_hash = request.cookies["wisesession"]
      session_id = parseInt(redisClient.get(sessionIdKey(session_hash)))
      session_new = false
    except:
      session_hash = startSession()
      session_id = parseInt(redisClient.get(sessionIdKey(session_hash)))
      session_new = true
      setCookie("wisesession", session_hash, daysForward(90))

    (session_id, session_hash, session_new)


# WEB PAGES

proc page_template(title: string, homeUrl: string) {.html_templ.} =
  html(lang="en"):
    head:
      title: title
    body:
      h1:
        a(href=homeUrl): title
      block content: discard
      block sync_assets: discard


proc docUploader(pageTitle: string) {.html_templ: page_template.} =
  title = pageTitle
  replace content:
    form(action="upload", `method`="post", enctype="multipart/form-data"):
      input(`type`="file", name="uploaded_files[]", multiple=true)
      input(`type`="submit", value="Upload")


proc docPreview(pageTitle: string, files: seq[string]) {.html_templ: page_template.} =
  title = pageTitle
  replace content:
    ul:
      for filename in files:
        li: pre: filename
  replace sync_assets:
    script(src="/reorder.js")

# ROUTING

routes:
  get "/":
    let (session_id, session_hash, session_new) = getSession()

    when defined(debug):
      echo "session_id = ",   session_id
      echo "session_hash = ", session_hash
      echo "session_new = ",  session_new

    resp:
      genHtml("docUploader", pageTitle="WISE Documentation Serializer")

  post "/upload":
    let (session_id, session_hash, session_new) = getSession()

    when defined(debug):
      echo "session_id = ",   session_id
      echo "session_hash = ", session_hash
      echo "session_new = ",  session_new

    var filenameList: seq[string] = @[]

    for v in values(request.formData):
      filenameList.add(v.fields["filename"])

    resp:
      genHtml("docPreview", pageTitle="WISE DS - Files Preview", files=filenameList)

    #resp(home())

  #get "/@id":
  #  let (session_id, session_hash, session_new) = getSession()
  #  echo session_id
  #  echo session_hash
  #  echo session_new
  #  resp("Session " & $session_id & " coming from hash " & @"id" & " with cookie " & request.cookies["wisesession"])


  #get "/":

  #post "/upload":
  #  var file = request.formData.getOrDefault("file")
  #  writeFile("uploaded.txt", file.body)
  #  discard execProcess("wgmkpdf 'Uploaded File' uploaded.txt uploaded.pdf", [])
  #  var s = readFile("uploaded.pdf")
  #  
  #  attachment("uploaded.pdf")
  #  resp(s)

runForever()

