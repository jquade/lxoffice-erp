#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
######################################################################
#
# Stuff that can be used from other modules
#
######################################################################

use List::Util qw(max);

use SL::Form;
use SL::Common;
use SL::MoreCommon;
use SL::ReportGenerator;

sub report_generator_export_as_pdf {
  $lxdebug->enter_sub();

  if ($form->{report_generator_pdf_options_set}) {
    my $saved_form = save_form();

    report_generator_do('PDF');

    if ($form->{report_generator_printed}) {
      restore_form($saved_form);
      $form->{MESSAGE} = $locale->text('The list has been printed.');
      report_generator_do('HTML');
    }

    $lxdebug->leave_sub();
    return;
  }

  my @form_values;
  map { push @form_values, { 'key' => $_, 'value' => $form->{$_} } } keys %{ $form };

  $form->get_lists('printers' => 'ALL_PRINTERS');
  map { $_->{selected} = $myconfig{default_printer_id} == $_->{id} } @{ $form->{ALL_PRINTERS} };

  $form->{copies} = max $myconfig{copies} * 1, 1;

  $form->{title} = $locale->text('PDF export -- options');
  $form->header();
  print $form->parse_html_template('report_generator/pdf_export_options',
                                   { 'HIDDEN'         => \@form_values,
                                     'default_margin' => $form->format_amount(\%myconfig, 1.5),
                                     'SHOW_PRINTERS'  => scalar @{ $form->{ALL_PRINTERS} },
                                   });

  $lxdebug->leave_sub();
}

sub report_generator_export_as_csv {
  $lxdebug->enter_sub();

  if ($form->{report_generator_csv_options_set}) {
    report_generator_do('CSV');
    $lxdebug->leave_sub();
    return;
  }

  my @form_values;
  map { push @form_values, { 'key' => $_, 'value' => $form->{$_} } } keys %{ $form };

  $form->{title} = $locale->text('CSV export -- options');
  $form->header();
  print $form->parse_html_template('report_generator/csv_export_options', { 'HIDDEN' => \@form_values });

  $lxdebug->leave_sub();
}

sub report_generator_back {
  $lxdebug->enter_sub();

  report_generator_do('HTML');

  $lxdebug->leave_sub();
}

sub report_generator_do {
  $lxdebug->enter_sub();

  my $format  = shift;

  my $nextsub = $form->{report_generator_nextsub};
  if (!$nextsub) {
    $form->error($locale->text('report_generator_nextsub is not defined.'));
  }

  foreach my $key (split m/ +/, $form->{report_generator_variable_list}) {
    $form->{$key} = $form->{"report_generator_hidden_${key}"};
  }

  $form->{report_generator_output_format} = $format;

  delete @{$form}{map { "report_generator_$_" } qw(nextsub variable_list)};

  call_sub($nextsub);

  $lxdebug->leave_sub();
}

sub report_generator_dispatcher {
  $lxdebug->enter_sub();

  my $nextsub = $form->{report_generator_dispatch_to};
  if (!$nextsub) {
    $form->error($locale->text('report_generator_dispatch_to is not defined.'));
  }

  delete $form->{report_generator_dispatch_to};

  call_sub($nextsub);

  $lxdebug->leave_sub();
}

1;