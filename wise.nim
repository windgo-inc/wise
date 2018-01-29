# Copyright <YEAR> <COPYRIGHT HOLDER>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


import macros, future
import os, osproc, re, jester, htmlgen, asyncnet, random
import sequtils, strutils, streams, times
import tables, hashes, redis, emerald
import asyncdispatch

import nimPDF/nimPDF


# VERSION

const WISEMajorVersion = "0"
const WISEMinorVersion = "1"
const WISEVersion = WISEMajorVersion & "." & WISEMinorVersion


# TYPES

type
  FileAction = enum
    NoFileAction,
    ImageToPDFFileAction,
    TextToPDFFileAction

  FileInfo = object
    rotatable: bool
    rot_cw: bool
    title: string
    filename: string
    mimetype: string
    basename: string
    extension: string
    data: string

  FileInfoRef = ref FileInfo

  FileActionSeq = seq[tuple[info: FileInfoRef, action: FileAction]]

  MultiDataValue = tuple[fields: StringTableRef, body: string]


# FILEINFO

proc hashFileInfo(info: FileInfoRef, session_hash: string): string {.noSideEffect.} =
  let
    filehash = [
      session_hash,
      info.filename,
      info.mimetype,
      info.data[0..min(311, info.data.len)]
    ].join("//").hash

  $(!$filehash)


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

  x.title = x.basename
  x.rotatable = true


proc newFileInfo(data: MultiDataValue): FileInfoRef =
  newFileInfo(result, data)


# MISC

proc upload_path(session_hash: string): string =
  "svc/uploads-" & session_hash & "/"


# PDF PREPRESS

proc draw_title(doc: Document, text:string) =
  let size = getSizeFromName("Letter")

  doc.setFont("TimesNewRoman", {FS_BOLD}, 5)
  let tw = doc.getTextWidth(text)
  let x = size.width.toMM/2 - tw/2

  doc.setRGBFill(0,0,0)
  doc.drawText(x, 10.0, text)
  #doc.setRGBStroke(0,0,0)
  #doc.drawRect(10,15,size.width.toMM - 20, size.height.toMM-25)
  doc.stroke()

proc image_pdf(session: string, figname: string, inname: string, outname: string, no_rotate: bool = false, rot_cw: bool = false): bool {.discardable.} =
  var file = newFileStream(outname, fmWrite)

  result = false
  if not file.isNil:
    var opts = makeDocOpt()
    let size = getSizeFromName("Letter")

    opts.addFontsPath("svc/fonts")
    opts.addImagesPath(".")
    #opts.addImagesPath("svc/uploads-" & session)
    opts.addResourcesPath("svc/fonts")

    var doc = initPDF(opts)
    doc.addPage(getSizeFromName("Letter"))
    
    var
      image = doc.loadImage(inname)

    echo inname

    if not image.isNil:
      let
        cli_h = size.height.toMM - 30.0
        cli_w = fromIN(fromMM(size.width.toMM - 10.0).toIN - 1.0).toMM
      
        is_landscape: bool = image.width > image.height
        is_too_wide: bool = image.width.float > fromMM(cli_w).toPT
        rot90: bool = (not no_rotate) and is_landscape and is_too_wide

        imgw = float(if rot90: image.height else: image.width)
        imgh = float(if rot90: image.width  else: image.height)

      doc.draw_title(figname)

      var
        ws = fromMM(cli_w).toPT / imgw
        hs = fromMM(cli_h).toPT / imgh
        scale = min(1.0, min(ws, hs))

        scl_w = fromPT(imgw).toMM * scale
        scl_h = fromPT(imgh).toMM * scale

        diff_w = cli_w - scl_w
        diff_h = cli_h - scl_h

        x = fromIN(1.0).toMM + diff_w / 2.0
        y = fromPT(size.height.toPT - fromMM(10.0).toPT).toMM - diff_h / 2.0

      if rot90 and not rot_cw:
        doc.rotate(90.0, x, y)
        doc.move(0.0, scl_w)
      elif rot90 and rot_cw:
        doc.rotate(-90.0, x, y)
        doc.move(-scl_h, 0.0)
      doc.stretch(scale, scale, x, y)
      doc.drawImage(x, y, image)
    else:
      doc.draw_title("LOAD ERROR [" & inname & "]")

    doc.setInfo(DI_TITLE, figname & " " & getDateStr())
    doc.setInfo(DI_AUTHOR, "WINDGO, Inc.")
    doc.setInfo(DI_SUBJECT, "WINDGO Documentation" & getDateStr())

    doc.writePDF(file)
    file.close()
    
    result = true


proc prepress_pdf(session: string, actions: FileActionSeq): string =
  let
    outfile = [
      "user-" & session & "/",
      format(getLocalTime(getTime()), "yyyy-MM-dd-HH-mm-ss"),
      ".pdf"
    ].join
 
  var procs: seq[string]
  var results: seq[string]

  let thepath = upload_path(session)
  
  newSeq(procs, actions.len)
  newSeq(results, actions.len)

  for i, what in pairs(actions):
    results[i] = thepath & what.info.filename & ".pdf"
    case what.action:
      of ImageToPDFFileAction:
        procs[i] = "touch " & thepath & ".nothing"
        image_pdf(session, what.info.title, thepath & what.info.filename, results[i], not what.info.rotatable, what.info.rot_cw)
      of TextToPDFFileAction:
        procs[i] = [
          "cd ", quoteShell(thepath), " && ",
          "wgmkpdf ",
          quoteShell(what.info.basename), " ",
          quoteShell(what.info.filename), " ",
          quoteShell(what.info.filename & ".pdf")
        ].join
      else:
        procs[i] = "touch " & thepath & ".nothing"
        results[i] = thepath & what.info.filename

  if execProcesses(procs) == 0:
    createDir("public/user-" & session)
    discard execProcess([
      "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=",
      quoteShell("public/" & outfile),
      " ",
      results.map(quoteShell).join(" ")].join)

    result = outfile
  else:
    raise newException(OSError, "Could not convert files to PDFs.")

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
      setCookie("wisesession", session_hash, daysForward(90))
    except:
      session_hash = start_session()
      session_id = parseInt(redisClient.get(sessionIdKey(session_hash)))
      session_new = true

    (session_id, session_hash, session_new)


macro use_session(body: untyped): untyped =
  result = newStmtList(parseStmt"let (session_id, session_hash, is_new_session) = get_session()")
  result.add(body)

# WEB PAGES

proc page_template(title: string, homeUrl: string) {.html_templ.} =
  html(lang="en"):
    head:
      title: "WISE Document Compiler - " & title
      
      meta(http_equiv="Cache-Control", content="no-cache, no-store, must-revalidate")
      meta(http_equiv="Pragma", content="no-cache")
      meta(http_equiv="Expires", content="0")

      link(href="/jquery-ui.min.css", rel="stylesheet"): ""
      link(href="/jquery-ui.theme.min.css", rel="stylesheet"): ""

      script(`type`="text/javascript", src="/jquery-3.3.1.min.js"): ""
      script(`type`="text/javascript", src="/jquery-ui.min.js"): ""

      style:
        block style_ex: discard
      block sync_assets: discard
    body:
      h1:
        a(href=homeUrl): "WISE Document Compiler - " & title
      block content: discard


proc docUploader(pageTitle: string) {.html_templ: page_template.} =
  title = pageTitle
  replace sync_assets:
    script(`type`="text/javascript"):
      """
      $(document).ready(function () {
        $("#upload-form").attr('action', '/upload/' + (new Date()).getTime());
      });
      """
  replace content:
    p: """
       This is an on-line tool for internal use at WINDGO Research Laboratory
       designed to help you document by combining a sequence of files in to
       a single document quickly.
       """
    p: """
       Start by uploading your files. Supported file formats are given in the
       following list. Note that any files not explicitly supported will be
       intepreted as plain text files. This design choice is driven by the
       frequent need to assemble source files as part of documentation.
       """
    ul:
      li: "Text (.txt)"
      li: "Portable Document Format (.pdf)"
      li: "Windows Bitmap Image Format (.bmp)"
      li: "Portable Network Graphics Image Format (.png)"
      li: "Joint Photographic Experts Group Image Format (.jpg|.jpeg)"
      li: "Targa Image Format (.tga|.targa)"

    h3: "Select Files"
    form(id="upload-form", `method`="post", enctype="multipart/form-data"):
      input(`type`="file", name="uploaded_files[]", multiple=true)
      input(`type`="submit", value="Upload")


proc docPreview(pageTitle: string, files: seq[string]) {.html_templ: page_template.} =
  title = pageTitle
  replace style_ex: """
    #filelist { list-style-type: none; margin: 0; padding: 0; }
    """

  replace content:
    #p:
    #  "Use the Up and Down buttons to choose the order of serialization for the final PDF."
    p: """
      Click and drag the filenames to select the order and then click
      'Generate'! Please note that the figure title and rotation options apply
      only to images.
      """

    ul(id="filelist"):
      for i, filename in pairs(files):
        li(id=["fileno", $i].join):
          span(class="ui-icon ui-icon-arrowthick-2-n-s"): ""
          span(id=["fig-props", $i].join, class="figure-props"): ""
          span(class="uploaded-figure"): filename
          span(class="figure-props-show"): ""

          #button(id=["up", $i].join): "[Up ↑]"
          #button(id=["dn", $i].join): "[Down ↓]"

    br()
    form(id="generateform", action="/generate", `method`="post", enctype="application/x-www-form-urlencoded"):
      input(`type`="hidden", name="order", value="", id="genorder")
      input(`type`="submit", value="Generate PDF")

    `div`(id="result-link"): ""
    
  replace sync_assets:
    script(src="/reorder.js")


# ROUTING

# The keys to this table are made from a hash of the session, filename, and data.
# The files are only stored transiently.
var fileTable = initTable[string, FileInfoRef]()
var fileListTable = initTable[string, seq[string]]()


routes:
  get "/":
    setCookie("wisesession", start_session(), daysForward(90))
    resp:
      genHtml("docUploader", pageTitle="Step 1 - Upload your files.")

  post "/upload/@whichupload":
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

      let
        fileInfoList = sequtils.map(
          fileListTable[session_hash], file_hash => fileTable[file_hash])
        filenameList = sequtils.map(
          fileInfoList,
          info => [info.filename, info.mimetype].join(" : "))

      resp:
        genHtml("docPreview", pageTitle="Step 2 - Arrange your files.", files=filenameList)

  post "/generate/@whichupload":
    use_session:
      let
        order = request.params["order"].split(' ').map(parseInt)
        canrot = request.params["canrot"].split(' ').map(x => bool(parseInt(x)))
        revrot = request.params["revrot"].split(' ').map(x => bool(parseInt(x)))
        names = request.params["names"].split("#####")
        inputFileList = fileListTable[session_hash]

      echo order
      echo canrot
      echo revrot
      echo names

      var
        fileList: seq[string]
        fileActionList: FileActionSeq
        
      newSeq(fileList, order.len)
      newSeq(fileActionList, order.len)

      for i, j in pairs(order):
        fileList[i] = inputFileList[j]
        fileTable[fileList[i]].title = names[j]
        fileTable[fileList[i]].rotatable = canrot[j]
        fileTable[fileList[i]].rot_cw = revrot[j]

      let
        files = fileList.map(file_hash => fileTable[file_hash])

      createDir("svc/uploads-" & session_hash)

      for i, info in pairs(files):
        echo "FILE ", $i
        echo "  filename:  ", info.filename
        echo "  basename:  ", info.basename
        echo "  extension: ", if info.extension.isNil: "(no extension)" else: info.extension
        echo "  mimetype:  ", info.mimetype
        echo "  title:     ", info.title
        echo "  rotatable: ", info.rotatable
        echo "  rot_cw:    ", info.rot_cw

        writeFile(upload_path(session_hash) & info.filename, info.data)

        case info.mimetype:
          of "application/pdf":
            fileActionList[i] = (info: info, action: NoFileAction)
            echo "  -> no action."
          else:
            if info.mimetype.startsWith("image"):
              fileActionList[i] = (info: info, action: ImageToPDFFileAction)
              echo "  -> image to PDF."
              var
                willrotate =
                  if info.rotatable:
                    "image may be rotated to fit."
                  else:
                    "image will not be rotated to fit."
              echo "     ", willrotate
            else:
              fileActionList[i] = (info: info, action: TextToPDFFileAction)
              echo "  -> text to PDF."


      let
        outputFile = prepress_pdf(session_hash, fileActionList)

      resp: outputFile

redisClient = redis.open()
runForever()

