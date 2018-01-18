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

proc page_template(title: string, homeUrl: string) {.html_templ.} =
  html(lang="en"):
    head:
      title: title
    body:
      h1:
        a(href=homeUrl): title
      block content: discard

proc home() {.html_templ: page_template.} =
  title = "WISE Documentation Serializer"
  replace content:
    form(action="upload", `method`="post", enctype="multipart/form-data"):
      input(`type`="file", name="my_file[]", multiple=true)
      input(`type`="submit", value="Upload")

template respByTemplate(cons: untyped): untyped =
  var
    ss = newStringStream()
    r = cons()

  r.render(ss)
  resp(ss.data)

routes:
  get "/":
    let (session_id, session_hash, session_new) = getSession()

    echo "session_id = ",   session_id
    echo "session_hash = ", session_hash
    echo "session_new = ",  session_new

    respByTemplate(newHome)

  post "/upload":
    let (session_id, session_hash, session_new) = getSession()

    echo "session_id = ",   session_id
    echo "session_hash = ", session_hash
    echo "session_new = ",  session_new

    resp($request.formData)#.getOrDefault("file").filename)
    #redirect("/")
    #respByTemplate(newHome)


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

