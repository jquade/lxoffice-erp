if(!defined $sel) {
  require "t/selenium/AllTests.t";
  init_server("singlefileonly",$0);
  exit(0);
}
diag("Add show and delete measure");
SKIP: {
  start_login();
  
  $sel->click_ok("link=Maßeinheiten");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->select_frame_ok("main_window");
  $sel->type_ok("new_name", "ogge");
  $sel->select_ok("new_base_unit", "label=Stck");
  $sel->type_ok("new_factor", "3,5");
  $sel->type_ok("new_localized_" . $lxtest->{lang_id}, "kogge");
  $sel->type_ok("new_localized_plural_" . $lxtest->{lang_id}, "kogges");
  $sel->click_ok("action");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->type_ok("localized_1_" . $lxtest->{lang_id}, "gm");
  $sel->type_ok("localized_plural_1_" . $lxtest->{lang_id}, "gms");
  $sel->type_ok("localized_2_" . $lxtest->{lang_id}, "gg");
  $sel->type_ok("localized_plural_2_" . $lxtest->{lang_id}, "ggs");
  $sel->type_ok("localized_3_" . $lxtest->{lang_id}, "gk");
  $sel->type_ok("localized_plural_3_" . $lxtest->{lang_id}, "gks");
  $sel->type_ok("localized_4_" . $lxtest->{lang_id}, "tt");
  $sel->type_ok("localized_plural_4_" . $lxtest->{lang_id}, "tts");
  $sel->type_ok("localized_5_" . $lxtest->{lang_id}, "lm");
  $sel->type_ok("localized_plural_5_" . $lxtest->{lang_id}, "lms");
  $sel->type_ok("localized_6_" . $lxtest->{lang_id}, "LL");
  $sel->type_ok("localized_plural_6_" . $lxtest->{lang_id}, "LLs");
  $sel->type_ok("localized_7_" . $lxtest->{lang_id}, "kctS");
  $sel->type_ok("localized_plural_7_" . $lxtest->{lang_id}, "kctSs");
  $sel->click_ok("document.forms[0].action[1]");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->click_ok("delete_8");
  $sel->click_ok("//tr[9]/td[1]/a/img");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->click_ok("//tr[8]/td[1]/a[1]/img");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->click_ok("//tr[7]/td[1]/a[2]/img");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->click_ok("//tr[8]/td[1]/a[2]/img");
  $sel->wait_for_page_to_load($lxtest->{timeout});
  $sel->click_ok("delete_8");
  $sel->click_ok("document.forms[0].action[1]");
  $sel->wait_for_page_to_load($lxtest->{timeout});
};
1;