function set_history_uri() {
  document.location.href = "am.pl?" +
    "action=show_am_history&" +
    "login=" +  encodeURIComponent(document.getElementsByName("login")[0].value)+ "&"+
    "password=" + encodeURIComponent(document.getElementsByName("password")[0].value) + "&" +
    "longdescription=" + "&" +
    "einschraenkungen=" + document.getElementById("einschraenkungen").value + "&" +
    "transdate=" + document.getElementById("transdate_hidden").value + "&" +
    "regdate=" + document.getElementById("reqdate_hidden").value + "&" +
    "what2search=" + document.getElementById("what2search").value + "&" +
    "searchid=" + document.getElementById("searchid").value + "&" +
    "mitarbeiter=" + document.getElementById("mitarbeiter_hidden").value + "&";
}