# Package

version       = "0.1.0"
author        = "William Whitacre"
description   = "WINDGO Internal Service Endpoint"
license       = "All Rights Reserved"

# Dependencies

requires "nim >= 0.17.2"
requires "jester >= 0.2.0"
requires "redis >= 0.2.0"
requires "emerald >= 0.2.2"
requires "nimPDF >= 0.3.1"

skipDirs = @["test", "bootstrap", "public", "svc"]


