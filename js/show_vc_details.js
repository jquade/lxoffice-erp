function show_vc_details(vc) {
  var width = 750;
  var height = 550;
  var parm = centerParms(width, height) + ",width=" + width + ",height=" + height + ",status=yes,scrollbars=yes";
  var vc_id = document.getElementsByName(vc + "_id");
  if (vc_id)
    vc_id = vc_id[0].value;
  url = "common.pl?" +
    "action=show_vc_details&" +
    "login=" + escape(document.getElementsByName("login")[0].value) + "&" +
    "password=" + escape(document.getElementsByName("password")[0].value) + "&" +
    "vc=" + escape(vc) + "&" +
    "vc_id=" + escape(vc_id)
  //alert(url);
  window.open(url, "_new_generic", parm);
}