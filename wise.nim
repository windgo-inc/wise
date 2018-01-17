# Issue #22

import os, osproc, re, jester, asyncdispatch, htmlgen, asyncnet

routes:
  get "/":
    var html = ""
    #for file in walkFiles("*.*"):
    #  html.add "<li>" & file & "</li>"
    html.add "<h3>UNIX and Windows compatible plaintext serializer."
    html.add "<form action=\"upload\" method=\"post\"enctype=\"multipart/form-data\">"
    html.add "<input type=\"file\" name=\"file\"value=\"file\">"
    html.add "<input type=\"submit\" value=\"Submit\" name=\"submit\">"
    html.add "</form>"
    resp(html)

  post "/upload":
    var file = request.formData.getOrDefault("file")
    writeFile("uploaded.txt", file.body)
    discard execProcess("wgmkpdf 'Uploaded File' uploaded.txt uploaded.pdf", [])
    var s = readFile("uploaded.pdf")
    
    attachment("uploaded.pdf")
    resp(s)

runForever()

