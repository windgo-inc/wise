# Issue #22

import os, osproc, re, jester, asyncdispatch, htmlgen, asyncnet, random
import tables, hashes

const WISEMajorVersion = "0"
const WISEMinorVersion = "1"
const WISEVersion = WISEMajorVersion & "." & WISEMinorVersion

var session_counter: int = 0

type
  SessionData = int

var sessionTable = initTable[string, SessionData]()

proc startSession(): string =
  inc session_counter
  let r = !$(session_counter.hash)
  result = $r
  sessionTable[result] = session_counter


template getSession(): untyped =
  block:
    var session_hash: string
    var session_id: int
    var session_new: bool = true
    try:
      session_hash = request.cookies["wisesession"]
      session_id = sessionTable[session_hash]
      session_new = false
    except:
      session_hash = startSession()
      session_id = sessionTable[session_hash]
      session_new = true
      setCookie("wisesession", session_hash, daysForward(90))

    (session_id, session_hash, session_new)


routes:
  get "/":
    let (session_id, session_hash, session_new) = getSession()
    echo session_id
    echo session_hash
    echo session_new
    redirect("/" & session_hash)

  get "/@id":
    let (session_id, session_hash, session_new) = getSession()
    echo session_id
    echo session_hash
    echo session_new
    resp("Session " & $session_id & " coming from hash " & @"id" & " with cookie " & request.cookies["wisesession"])


  #get "/":
  #  var html = ""
  #  #for file in walkFiles("*.*"):
  #  #  html.add "<li>" & file & "</li>"
  #  html.add "<h3>UNIX and Windows compatible plaintext serializer."
  #  html.add "<form action=\"upload\" method=\"post\"enctype=\"multipart/form-data\">"
  #  html.add "<input type=\"file\" name=\"file\"value=\"file\">"
  #  html.add "<input type=\"submit\" value=\"Submit\" name=\"submit\">"
  #  html.add "</form>"
  #  resp(html)

  #post "/upload":
  #  var file = request.formData.getOrDefault("file")
  #  writeFile("uploaded.txt", file.body)
  #  discard execProcess("wgmkpdf 'Uploaded File' uploaded.txt uploaded.pdf", [])
  #  var s = readFile("uploaded.pdf")
  #  
  #  attachment("uploaded.pdf")
  #  resp(s)

runForever()

