// reorder.js

var figureNames = {};
var figuresAllowRotate = {};

function filenoToFigpropsId(theId) {
  return "fig-props" + theId.slice(6);
}

function figpropsToFilenoId(theId) {
  return "fileno" + theId.slice(9);
}

function filenoIdToNum(theId) {
  return parseInt(theId.slice(6));
}

function filenoToRotId(theId) {
  return "rot" + theId;
}

function rotToFilenoId(theId) {
  return theId.slice(3);
}

$(document).ready(function () {
  $("#filelist").sortable();
  $("#filelist").disableSelection();

  $(".uploaded-figure").disableSelection();

  $(".figure-props").each(function () {
    var conf_id = $(this).attr('id');
    var li_id = figpropsToFilenoId(conf_id);
    var fig_no = filenoIdToNum(li_id);

    var $figproparea = $("#" + li_id + " .figure-props-show");

    var fileinfostr = $('#' + li_id + " .uploaded-figure").text();
    var fileinfosep = fileinfostr.lastIndexOf(':') - 1;

    if (fileinfosep > 0) {
      fileinfostr = fileinfostr.slice(0, fileinfosep);
    }

    fileinfosep = fileinfostr.lastIndexOf('.');
    if (fileinfosep > 0) {
      fileinfostr = fileinfostr.slice(0, fileinfosep);
    }

    var $opsdiv = $('<div>')
    $opsdiv.css('margin-left', '1cm');
    $opsdiv.css('display', 'none');

    var $theinput = $('<input>', {
      type: 'text',
      id: 'figname'+li_id,
      val: fileinfostr
    });

    var $allowrot = $('<input />', {
      type: 'checkbox',
      id: 'rot'+li_id,
      value: "Allow Fit Rotation"
    });

    $opsdiv.append($('<span>').text("Figure Title: "));
    $opsdiv.append($theinput);
    $opsdiv.append($('<br>'));
    $opsdiv.append($allowrot);
    $opsdiv.append(
      $('<label />', { 'for': 'rot'+li_id, text: "Allow Fit Rotation" })
    );

    $figproparea.html('');
    $figproparea.append($opsdiv);

    //$theinput.focus();
    $allowrot.prop('checked', true);

    $theinput.change(function () {
      figureNames[fig_no] = $(this).val();
    });

    $allowrot.change(function () {
      figuresAllowRotate[fig_no] = $(this).prop('checked');
    });

    figureNames[fig_no] = fileinfostr;
    figuresAllowRotate[fig_no] = true;

    $opsdiv.slideDown("slow");
  });

  $("#generateform").submit(function (e) {
    var order = $("#filelist").children().map(function () {
      return $(this).attr('id');
    }).get();

    var ids = [], names = [], canrot = [];

    for (var i = 0; i < order.length; i++) {
      ids.push(order[i].slice(6));
    }

    console.log("ids = ", ids);

    for (var i = 0; i < ids.length; i++) {
      var escaped = figureNames[i].replace(/#####/g,"");
      //escaped = escaped.replace(/ /g,String.fromCharCode(92));
      names.push(escaped);
      if (figuresAllowRotate[i]) {
        canrot.push('1');
      } else {
        canrot.push('0');
      }
    }

    var parts = "order=" + encodeURIComponent(ids.join(' '));
    parts = parts + "&names=" + encodeURIComponent(names.join('#####'));
    parts = parts + "&canrot=" + encodeURIComponent(canrot.join(' '));

    $("#result-link").html('');
    $("#result-link").append($('<div>').text("Generating, please be patient."));
    $.ajax({
      type: "POST",
      url: "/generate",
      data: "?" + parts,
      success: function (response_data) {
        var url = window.location.protocol + "//" + window.location.host + "/";
        url = url + response_data;

        $("#result-link").html('');
        $("#result-link").append($('<a>').attr('href', url).attr("target", "_blank").text("Download!"));
      },
      error: function (xhr, status, error) {
        $("#result-link").html('');
        $("#result-link").append($('<div>').text("Something went wrong! :( " + error));
      }
    });

    e.preventDefault();
  });
});

