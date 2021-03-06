use strict;

use List::MoreUtils qw(any none uniq);
use List::Util qw(first);
use POSIX qw(strftime);

use SL::BankAccount;
use SL::Chart;
use SL::CT;
use SL::Form;
use SL::ReportGenerator;
use SL::SEPA;
use SL::SEPA::XML;

require "bin/mozilla/common.pl";
require "bin/mozilla/reportgenerator.pl";

sub bank_transfer_add {
  $main::lxdebug->enter_sub();

  my $form          = $main::form;
  my $locale        = $main::locale;

  $form->{title}    = $locale->text('Prepare bank transfer via SEPA XML');

  my $bank_accounts = SL::BankAccount->list();

  if (!scalar @{ $bank_accounts }) {
    $form->error($locale->text('You have not added bank accounts yet.'));
  }

  my $invoices = SL::SEPA->retrieve_open_invoices();

  if (!scalar @{ $invoices }) {
    $form->show_generic_information($locale->text('Either there are no open invoices, or you have already initiated bank transfers ' .
                                                  'with the open amounts for those that are still open.'));
    $main::lxdebug->leave_sub();
    return;
  }

  my $bank_account_label_sub = sub { $locale->text('Account number #1, bank code #2, #3', $_[0]->{account_number}, $_[0]->{bank_code}, $_[0]->{bank}) };

  $form->header();
  print $form->parse_html_template('sepa/bank_transfer_add',
                                   { 'INVOICES'           => $invoices,
                                     'BANK_ACCOUNTS'      => $bank_accounts,
                                     'bank_account_label' => $bank_account_label_sub, });

  $main::lxdebug->leave_sub();
}

sub bank_transfer_create {
  $main::lxdebug->enter_sub();

  my $form          = $main::form;
  my $locale        = $main::locale;
  my $myconfig      = \%main::myconfig;

  $form->{title}    = $locale->text('Create bank transfer via SEPA XML');

  my $bank_accounts = SL::BankAccount->list();

  if (!scalar @{ $bank_accounts }) {
    $form->error($locale->text('You have not added bank accounts yet.'));
  }

  my $bank_account = first { $form->{bank_account}->{id} == $_->{id} } @{ $bank_accounts };

  if (!$bank_account) {
    $form->error($locale->text('The selected bank account does not exist anymore.'));
  }

  my $invoices       = SL::SEPA->retrieve_open_invoices();
  my %invoices_map   = map { $_->{id} => $_ } @{ $invoices };
  my @bank_transfers =
    map  +{ %{ $invoices_map{ $_->{ap_id} } }, %{ $_ } },
    grep  { $_->{selected} && (0 < $_->{amount}) && $invoices_map{ $_->{ap_id} } }
    map   { $_->{amount} = $form->parse_amount($myconfig, $_->{amount}); $_ }
          @{ $form->{bank_transfers} || [] };

  if (!scalar @bank_transfers) {
    $form->error($locale->text('You have selected none of the invoices.'));
  }

  my ($vendor_bank_info);
  my $error_message;

  if ($form->{confirmation}) {
    $vendor_bank_info = { map { $_->{id} => $_ } @{ $form->{vendor_bank_info} || [] } };

    foreach my $info (values %{ $vendor_bank_info }) {
      if (any { !$info->{$_} } qw(iban bic)) {
        $error_message = $locale->text('The bank information must not be empty.');
        last;
      }
    }
  }

  if ($error_message || !$form->{confirmation}) {
    my @vendor_ids             = uniq map { $_->{vendor_id} } @bank_transfers;
    $vendor_bank_info        ||= CT->get_bank_info('vc' => 'vendor',
                                                   'id' => \@vendor_ids);
    my @vendor_bank_info       = sort { lc $a->{name} cmp lc $b->{name} } values %{ $vendor_bank_info };

    my $bank_account_label_sub = sub { $locale->text('Account number #1, bank code #2, #3', $_[0]->{account_number}, $_[0]->{bank_code}, $_[0]->{bank}) };

    $form->{jsscript}          = 1;

    $form->header();
    print $form->parse_html_template('sepa/bank_transfer_create',
                                     { 'BANK_TRANSFERS'     => \@bank_transfers,
                                       'BANK_ACCOUNTS'      => $bank_accounts,
                                       'VENDOR_BANK_INFO'   => \@vendor_bank_info,
                                       'bank_account'       => $bank_account,
                                       'bank_account_label' => $bank_account_label_sub,
                                       'error_message'      => $error_message,
                                     });

  } else {
    foreach my $bank_transfer (@bank_transfers) {
      foreach (qw(iban bic)) {
        $bank_transfer->{"vendor_${_}"} = $vendor_bank_info->{ $bank_transfer->{vendor_id} }->{$_};
        $bank_transfer->{"our_${_}"}    = $bank_account->{$_};
      }

      $bank_transfer->{chart_id} = $bank_account->{chart_id};
    }

    my $id = SL::SEPA->create_export('employee'       => $form->{login},
                                     'bank_transfers' => \@bank_transfers);

    $form->header();
    print $form->parse_html_template('sepa/bank_transfer_created', { 'id' => $id });
  }

  $main::lxdebug->leave_sub();
}

sub bank_transfer_search {
  $main::lxdebug->enter_sub();

  my $form   = $main::form;
  my $locale = $main::locale;

  $form->{title}    = $locale->text('List of bank transfers');
  $form->{jsscript} = 1;

  $form->header();
  print $form->parse_html_template('sepa/bank_transfer_search');

  $main::lxdebug->leave_sub();
}


sub bank_transfer_list {
  $main::lxdebug->enter_sub();

  my $form   = $main::form;
  my $locale = $main::locale;
  my $cgi    = $main::cgi;

  $form->{title}     = $locale->text('List of bank transfers');

  $form->{sort}    ||= 'id';
  $form->{sortdir}   = '1' if (!defined $form->{sortdir});

  $form->{callback}  = build_std_url('action=bank_transfer_list', 'sort', 'sortdir');

  my %filter         = map  +( $_ => $form->{"f_${_}"} ),
                       grep  { $form->{"f_${_}"} }
                             (qw(vendor invnumber),
                              map { ("${_}_date_from", "${_}_date_to") }
                                  qw(export requested_execution execution));
  $filter{executed}  = $form->{l_executed} ? 1 : 0 if ($form->{l_executed} != $form->{l_not_executed});
  $filter{closed}    = $form->{l_closed}   ? 1 : 0 if ($form->{l_open}     != $form->{l_closed});

  my $exports        = SL::SEPA->list_exports('filter'    => \%filter,
                                              'sortorder' => $form->{sort},
                                              'sortdir'   => $form->{sortdir});

  my $open_available = any { !$_->{closed} } @{ $exports };

  my $report         = SL::ReportGenerator->new(\%main::myconfig, $form);

  my @hidden_vars    = grep { m/^[fl]_/ && $form->{$_} } keys %{ $form };

  my $href           = build_std_url('action=bank_transfer_list', @hidden_vars);

  my %column_defs = (
    'selected'    => { 'text' => $cgi->checkbox(-name => 'select_all', -id => 'select_all', -label => ''), },
    'id'          => { 'text' => $locale->text('Number'), },
    'export_date' => { 'text' => $locale->text('Export date'), },
    'employee'    => { 'text' => $locale->text('Employee'), },
    'executed'    => { 'text' => $locale->text('Executed'), },
    'closed'      => { 'text' => $locale->text('Closed'), },
  );

  my @columns = qw(selected id export_date employee executed closed);

  foreach my $name (qw(id export_date employee executed closed)) {
    my $sortdir                 = $form->{sort} eq $name ? 1 - $form->{sortdir} : $form->{sortdir};
    $column_defs{$name}->{link} = $href . "&sort=$name&sortdir=$sortdir";
  }

  $column_defs{selected}->{visible} = $open_available                                ? 1 : 0;
  $column_defs{executed}->{visible} = $form->{l_executed} && $form->{l_not_executed} ? 1 : 0;
  $column_defs{closed}->{visible}   = $form->{l_closed}   && $form->{l_open}         ? 1 : 0;

  my @options = ();
  push @options, $locale->text('Vendor')                        . ' : ' . $form->{f_vendor}                        if ($form->{f_vendor});
  push @options, $locale->text('Invoice number')                . ' : ' . $form->{f_invnumber}                     if ($form->{f_invnumber});
  push @options, $locale->text('Export date from')              . ' : ' . $form->{f_export_date_from}              if ($form->{f_export_date_from});
  push @options, $locale->text('Export date to')                . ' : ' . $form->{f_export_date_to}                if ($form->{f_export_date_to});
  push @options, $locale->text('Requested execution date from') . ' : ' . $form->{f_requested_execution_date_from} if ($form->{f_requested_execution_date_from});
  push @options, $locale->text('Requested execution date to')   . ' : ' . $form->{f_requested_execution_date_to}   if ($form->{f_requested_execution_date_to});
  push @options, $locale->text('Execution date from')           . ' : ' . $form->{f_execution_date_from}           if ($form->{f_execution_date_from});
  push @options, $locale->text('Execution date to')             . ' : ' . $form->{f_execution_date_to}             if ($form->{f_execution_date_to});
  push @options, $form->{l_executed} ? $locale->text('executed') : $locale->text('not yet executed')               if ($form->{l_executed} != $form->{l_not_executed});
  push @options, $form->{l_closed}   ? $locale->text('closed')   : $locale->text('open')                           if ($form->{l_open}     != $form->{l_closed});

  $report->set_options('top_info_text'         => join("\n", @options),
                       'raw_top_info_text'     => $form->parse_html_template('sepa/bank_transfer_list_top'),
                       'raw_bottom_info_text'  => $form->parse_html_template('sepa/bank_transfer_list_bottom', { 'show_buttons' => $open_available }),
                       'std_column_visibility' => 1,
                       'output_format'         => 'HTML',
                       'title'                 => $form->{title},
                       'attachment_basename'   => $locale->text('banktransfers') . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);
  $report->set_export_options('bank_transfer_list', @hidden_vars);
  $report->set_sort_indicator($form->{sort}, $form->{sortdir});

  my $edit_url = build_std_url('action=bank_transfer_edit', 'callback');

  foreach my $export (@{ $exports }) {
    my $row = { map { $_ => { 'data' => $export->{$_} } } keys %{ $export } };

    map { $row->{$_}->{data} = $export->{$_} ? $locale->text('yes') : $locale->text('no') } qw(executed closed);

    $row->{id}->{link} = $edit_url . '&id=' . E($export->{id});

    if (!$export->{closed}) {
      $row->{selected}->{raw_data} =
          $cgi->hidden(-name => "exports[+].id", -value => $export->{id})
        . $cgi->checkbox(-name => "exports[].selected", -value => 1, -label => '');
    }

    $report->add_data($row);
  }

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub bank_transfer_edit {
  $main::lxdebug->enter_sub();

  my $form   = $main::form;
  my $locale = $main::locale;

  my @ids    = ();
  if (!$form->{mode} || ($form->{mode} eq 'single')) {
    push @ids, $form->{id};
  } else {
    @ids = map $_->{id}, grep { $_->{selected} } @{ $form->{exports} || [] };

    if (!@ids) {
      $form->show_generic_error($locale->text('You have not selected any export.'), 'back_button' => 1);
    }
  }

  my $export;

  foreach my $id (@ids) {
    my $curr_export = SL::SEPA->retrieve_export('id' => $id, 'details' => 1);

    foreach my $item (@{ $curr_export->{items} }) {
      map { $item->{"export_${_}"} = $curr_export->{$_} } grep { !ref $curr_export->{$_} } keys %{ $curr_export };
    }

    if (!$export) {
      $export = $curr_export;
    } else {
      push @{ $export->{items} }, @{ $curr_export->{items} };
    }
  }

  if ($form->{mode} && ($form->{mode} eq 'multi')) {
    $export->{items} = [ grep { !$_->{export_closed} && !$_->{executed} } @{ $export->{items} } ];

    if (!@{ $export->{items} }) {
      $form->show_generic_error($locale->text('All the selected exports have already been closed, or all of their items have already been executed.'), 'back_button' => 1);
    }

  } elsif (!$export) {
    $form->error($locale->text('That export does not exist.'));
  }

  $form->{jsscript} = 1;
  $form->{title}    = $locale->text('View SEPA export');
  $form->header();
  print $form->parse_html_template('sepa/bank_transfer_edit',
                                   { 'ids'                       => \@ids,
                                     'export'                    => $export,
                                     'current_date'              => $form->current_date(\%main::myconfig),
                                     'show_post_payments_button' => any { !$_->{export_closed} && !$_->{executed} } @{ $export->{items} },
                                   });

  $main::lxdebug->leave_sub();
}

sub bank_transfer_post_payments {
  $main::lxdebug->enter_sub();

  my $form   = $main::form;
  my $locale = $main::locale;

  my @items  = grep { $_->{selected} } @{ $form->{items} || [] };

  if (!@items) {
    $form->show_generic_error($locale->text('You have not selected any item.'), 'back_button' => 1);
  }
  my @export_ids    = uniq map { $_->{sepa_export_id} } @items;
  my %exports       = map { $_ => SL::SEPA->retrieve_export('id' => $_, 'details' => 1) } @export_ids;
  my @items_to_post = ();

  foreach my $item (@items) {
    my $export = $exports{ $item->{sepa_export_id} };
    next if (!$export || $export->{closed} || $export->{executed});

    push @items_to_post, $item if (none { ($_->{id} == $item->{id}) && $_->{executed} } @{ $export->{items} });
  }

  if (!@items_to_post) {
    $form->show_generic_error($locale->text('All the selected exports have already been closed, or all of their items have already been executed.'), 'back_button' => 1);
  }

  if (any { !$_->{execution_date} } @items_to_post) {
    $form->show_generic_error($locale->text('You have to specify an execution date for each antry.'), 'back_button' => 1);
  }

  SL::SEPA->post_payment('items' => \@items_to_post);

  $form->show_generic_information($locale->text('The payments have been posted.'));

  $main::lxdebug->leave_sub();
}

sub bank_transfer_payment_list_as_pdf {
  $main::lxdebug->enter_sub();

  my $form       = $main::form;
  my %myconfig   = %main::myconfig;
  my $locale     = $main::locale;

  my @ids        = @{ $form->{items} || [] };
  my @export_ids = uniq map { $_->{export_id} } @ids;

  $form->show_generic_error($locale->text('Multi mode not supported.'), 'back_button' => 1) if 1 != scalar @export_ids;

  my $export = SL::SEPA->retrieve_export('id' => $export_ids[0], 'details' => 1);
  my @items  = ();

  foreach my $id (@ids) {
    my $item = first { $_->{id} == $id->{id} } @{ $export->{items} };
    push @items, $item if $item;
  }

  $form->show_generic_error($locale->text('No transfers were executed in this export.'), 'back_button' => 1) if 1 > scalar @items;

  my $report         =  SL::ReportGenerator->new(\%main::myconfig, $form);

  my %column_defs    =  (
    'invnumber'      => { 'text' => $locale->text('Invoice'), },
    'vendor_name'    => { 'text' => $locale->text('Vendor'), },
    'our_iban'       => { 'text' => $locale->text('Source IBAN'), },
    'our_bic'        => { 'text' => $locale->text('Source BIC'), },
    'vendor_iban'    => { 'text' => $locale->text('Destination IBAN'), },
    'vendor_bic'     => { 'text' => $locale->text('Destination BIC'), },
    'amount'         => { 'text' => $locale->text('Amount'), },
    'reference'      => { 'text' => $locale->text('Reference'), },
    'execution_date' => { 'text' => $locale->text('Execution date'), },
  );

  map { $column_defs{$_}->{align} = 'right' } qw(amount execution_date);

  my @columns        =  qw(invnumber vendor_name our_iban our_bic vendor_iban vendor_bic amount reference execution_date);

  $report->set_options('std_column_visibility' => 1,
                       'output_format'         => 'PDF',
                       'title'                 => $locale->text('Bank transfer payment list for export #1', $export->{id}),
                       'attachment_basename'   => $locale->text('bank_transfer_payment_list_#1', $export->{id}) . strftime('_%Y%m%d', localtime time),
    );

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  foreach my $item (@items) {
    my $row                = { map { $_ => { 'data' => $item->{$_} } } @columns };
    $row->{amount}->{data} = $form->format_amount(\%myconfig, $item->{amount}, 2);

    $report->add_data($row);
  }

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub bank_transfer_download_sepa_xml {
  $main::lxdebug->enter_sub();

  my $form     =  $main::form;
  my $myconfig = \%main::myconfig;
  my $locale   =  $main::locale;
  my $cgi      =  $main::cgi;

  if (!$myconfig->{company}) {
    $form->show_generic_error($locale->text('You have to enter a company name in your user preferences (see the "Program" menu, "Preferences").'), 'back_button' => 1);
  }

  my @ids;
  if ($form->{mode} && ($form->{mode} eq 'multi')) {
     @ids = map $_->{id}, grep { $_->{selected} } @{ $form->{exports} || [] };

  } else {
    @ids = ($form->{id});
  }

  if (!@ids) {
    $form->show_generic_error($locale->text('You have not selected any export.'), 'back_button' => 1);
  }

  my @items = ();

  foreach my $id (@ids) {
    my $export = SL::SEPA->retrieve_export('id' => $id, 'details' => 1);
    push @items, grep { !$_->{executed} } @{ $export->{items} } if ($export && !$export->{closed});
  }

  if (!@items) {
    $form->show_generic_error($locale->text('All the selected exports have already been closed, or all of their items have already been executed.'), 'back_button' => 1);
  }

  my $message_id = strftime('MSG%Y%m%d%H%M%S', localtime) . sprintf('%06d', $$);

  my $sepa_xml   = SL::SEPA::XML->new('company'     => $myconfig->{company},
                                      'src_charset' => $main::dbcharset || 'ISO-8859-15',
                                      'message_id'  => $message_id,
                                      'grouped'     => 1,
    );

  foreach my $item (@items) {
    my $requested_execution_date;
    if ($item->{requested_execution_date}) {
      my ($yy, $mm, $dd)        = $locale->parse_date($myconfig, $item->{requested_execution_date});
      $requested_execution_date = sprintf '%04d-%02d-%02d', $yy, $mm, $dd;
    }

    $sepa_xml->add_transaction({ 'src_iban'       => $item->{our_iban},
                                 'src_bic'        => $item->{our_bic},
                                 'dst_iban'       => $item->{vendor_iban},
                                 'dst_bic'        => $item->{vendor_bic},
                                 'recipient'      => $item->{vendor_name},
                                 'amount'         => $item->{amount},
                                 'reference'      => $item->{reference},
                                 'execution_date' => $requested_execution_date,
                                 'end_to_end_id'  => $item->{end_to_end_id} });
  }

  my $xml = $sepa_xml->to_xml();

  print $cgi->header('-type'                => 'application/octet-stream',
                     '-content-disposition' => 'attachment; filename="SEPA_' . $message_id . '.cct"',
                     '-content-length'      => length $xml);
  print $xml;

  $main::lxdebug->leave_sub();
}

sub bank_transfer_mark_as_closed_step1 {
  $main::lxdebug->enter_sub();

  my $form       = $main::form;
  my $locale     = $main::locale;

  my @export_ids = map { $_->{id} } grep { $_->{selected} } @{ $form->{exports} || [] };

  if (!@export_ids) {
    $form->show_generic_error($locale->text('You have not selected any export.'), 'back_button' => 1);
  }

  my @open_export_ids = ();
  foreach my $id (@export_ids) {
    my $export = SL::SEPA->retrieve_export('id' => $id);
    push @open_export_ids, $id if (!$export->{closed});
  }

  if (!@open_export_ids) {
    $form->show_generic_error($locale->text('All of the exports you have selected were already closed.'), 'back_button' => 1);
  }

  $form->{title} = $locale->text('Close SEPA exports');
  $form->header();
  print $form->parse_html_template('sepa/bank_transfer_mark_as_closed_step1', { 'OPEN_EXPORT_IDS' => \@open_export_ids });

  $main::lxdebug->leave_sub();
}

sub bank_transfer_mark_as_closed_step2 {
  $main::lxdebug->enter_sub();

  my $form       = $main::form;
  my $locale     = $main::locale;

  map { SL::SEPA->close_export('id' => $_); } @{ $form->{open_export_ids} || [] };

  $form->{title} = $locale->text('Close SEPA exports');
  $form->header();
  $form->show_generic_information($locale->text('The selected exports have been closed.'));

  $main::lxdebug->leave_sub();
}

sub dispatcher {
  my $form = $main::form;

  foreach my $action (qw(bank_transfer_create bank_transfer_edit bank_transfer_list
                         bank_transfer_post_payments bank_transfer_download_sepa_xml
                         bank_transfer_mark_as_closed_step1 bank_transfer_mark_as_closed_step2
                         bank_transfer_payment_list_as_pdf)) {
    if ($form->{"action_${action}"}) {
      call_sub($action);
      return;
    }
  }

  $form->error($main::locale->text('No action defined.'));
}

1;
