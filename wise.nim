import macros, future
import os, osproc, re, jester, htmlgen, asyncnet, random
import sequtils, strutils, streams
import tables, hashes, redis, emerald
import asyncdispatch

const WISEMajorVersion = "0"
const WISEMinorVersion = "1"
const WISEVersion = WISEMajorVersion & "." & WISEMinorVersion

var
  redisClient: Redis

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


proc start_session(): string =
  let value = redisClient.incr("wise:session_counter")
  let r = !$(value.hash)
  result = $r
  redisClient.setk(sessionIdKey(result), $value)


template get_session(): untyped =
  block:
    var session_hash: string
    var session_id: int
    var session_new: bool = true
    try:
      session_hash = request.cookies["wisesession"]
      session_id = parseInt(redisClient.get(sessionIdKey(session_hash)))
      session_new = false
    except:
      session_hash = start_session()
      session_id = parseInt(redisClient.get(sessionIdKey(session_hash)))
      session_new = true
      setCookie("wisesession", session_hash, daysForward(90))

    (session_id, session_hash, session_new)


macro use_session(body: untyped): untyped =
  result = newStmtList(parseStmt"let (session_id, session_hash, is_new_session) = get_session()")
  result.add(body)

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

type
  FileInfo = object
    filename: string
    mimetype: string
    basename: string
    extension: string
    data: string

  FileInfoRef = ref FileInfo

proc hashFileInfo(info: FileInfoRef, session_hash: string): string {.noSideEffect.} =
  let
    filehash = [
      session_hash,
      info.filename,
      info.mimetype,
      info.data[0..min(311, info.data.len)]
    ].join("//").hash

  $(!$filehash)

type
  MultiDataValue = tuple[fields: StringTableRef, body: string]

proc newFileInfo(x: var FileInfoRef, data: MultiDataValue) =
  let filename = data.fields["filename"]
  let extpos = filename.rfind('.')

  new(x)
  x.filename = filename
  x.mimetype = data.fields["Content-Type"]
  if extpos > -1:
    x.extension = filename[extpos+1..^1]
    x.basename = filename[0..<extpos]
  else:
    x.extension = nil
    x.basename = filename
  x.data = data.body


proc newFileInfo(data: MultiDataValue): FileInfoRef =
  newFileInfo(result, data)


# The keys to this table are made from a hash of the session, filename, and data.
# The files are only stored transiently.
var fileTable = initTable[string, FileInfoRef]()
var fileListTable = initTable[string, seq[string]]()

routes:
  get "/":
    use_session:
      resp:
        genHtml("docUploader", pageTitle="WISE Documentation Serializer")

  post "/upload":
    use_session:
      var fileList: seq[string]
      newSeq(fileList, 0)

      for v in values(request.formData):
        # Iterate through the files submitted and add the full FileInfo to the
        # fileTable, and add the hash of each FileInfo to the fileList
        let info = newFileInfo(v)
        let file_hash = hashFileInfo(info, session_hash)

        fileTable.add(file_hash, info)
        fileList.add(file_hash)
        #filenameList.add()

      # Add the fileList to the fileListTable for the current session.
      fileListTable.add(session_hash, fileList)

      redirect"/order"

  get "/order":
    use_session:
      let fileInfoList = sequtils.map(fileListTable[session_hash], file_hash => fileTable[file_hash])
      let filenameList = sequtils.map(fileInfoList, info => info.filename & " - " & info.mimetype & " : Hash=" & info.hashFileInfo(session_hash))

      resp:
        genHtml("docPreview", pageTitle="WISE DS - Files Preview", files=filenameList)


  #get "/@id":
  #  let (session_id, session_hash, session_new) = get_session()
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
redisClient = redis.open()
runForever()

