// reorder.js

var list = document.getElementById("filelist").children;
var idlist = []

for (var i = 0; i < list.length; i++) {
  idlist.push(i);
}

console.log(list)
console.log(idlist)

function updateGenOrder() {
  genorder.value = String(idlist[0]);
  for (var i = 1; i < list.length; i++) {
    genorder.value += " " + String(idlist[i]);
  }
}

function makeMoveListener(i, moveBy) {
  return function() {
    var idx = idlist.findIndex(function (elem) { return elem == i; })
    var tidx = idx + moveBy

    if (tidx < 0) { tidx = 0; }
    else if (tidx >= list.length) { tidx = list.length - 1; }

    if (tidx != idx) {
      idlist.splice(tidx, 0, idlist.splice(idx, 1)[0]);
    }

    if (moveBy < 0) {
      filelist.insertBefore(this.parentNode, filelist.children[tidx]);
    } else if (moveBy > 0) {
      filelist.insertBefore(this.parentNode, filelist.children[tidx + 1]);
    }

    updateGenOrder();
  }
}

for (var i = 0; i < list.length; i++) {
  document.getElementById("up" + i).addEventListener("click", makeMoveListener(i, -1))
  document.getElementById("dn" + i).addEventListener("click", makeMoveListener(i, 1))
}

updateGenOrder();

