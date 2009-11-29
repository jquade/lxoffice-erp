#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (c) 1998-2002
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#======================================================================
#
# Genereal Ledger
#
#======================================================================

use POSIX qw(strftime);
use List::Util qw(sum);

use SL::FU;
use SL::GL;
use SL::IS;
use SL::PE;
use SL::ReportGenerator;

require "bin/mozilla/common.pl";
require "bin/mozilla/drafts.pl";
require "bin/mozilla/reportgenerator.pl";

use strict;

# this is for our long dates
# $locale->text('January')
# $locale->text('February')
# $locale->text('March')
# $locale->text('April')
# $locale->text('May ')
# $locale->text('June')
# $locale->text('July')
# $locale->text('August')
# $locale->text('September')
# $locale->text('October')
# $locale->text('November')
# $locale->text('December')

# this is for our short month
# $locale->text('Jan')
# $locale->text('Feb')
# $locale->text('Mar')
# $locale->text('Apr')
# $locale->text('May')
# $locale->text('Jun')
# $locale->text('Jul')
# $locale->text('Aug')
# $locale->text('Sep')
# $locale->text('Oct')
# $locale->text('Nov')
# $locale->text('Dec')

my $tax;
my $debitlock  = 0;
my $creditlock = 0;

sub add {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  return $main::lxdebug->leave_sub() if (load_draft_maybe());

  $form->{title} = "Add";

  $form->{callback} = "gl.pl?action=add" unless $form->{callback};

  # we use this only to set a default date (and previous id?) jq
  GL->transaction(\%myconfig, \%$form);
  # store for comparison

  map {
    $tax .=
      qq|<option value="$_->{id}--$_->{rate}">$_->{taxdescription}  |
      . ($_->{rate} * 100) . qq| %|
  } @{ $form->{TAX} };

  $form->{rowcount}  = 2;

  $form->{debit}  = 0;
  $form->{credit} = 0;
  $form->{tax}    = 0;

  # departments
  $form->all_departments(\%myconfig);
  if (@{ $form->{all_departments} || [] }) {
    $form->{selectdepartment} = "<option>\n";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  $form->{show_details} = $myconfig{show_form_details} unless defined $form->{show_details};

  &display_form(1);
  $main::lxdebug->leave_sub();

}

sub prepare_transaction {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  GL->transaction(\%myconfig, \%$form);

  map {
    $tax .=
      qq|<option value="$_->{id}--$_->{rate}">$_->{taxdescription}  |
      . ($_->{rate} * 100) . qq| %|
  } @{ $form->{TAX} };

  $form->{amount} = $form->format_amount(\%myconfig, $form->{amount}, 2);

  # departments
  $form->all_departments(\%myconfig);
  if (@{ $form->{all_departments} || [] }) {
    $form->{selectdepartment} = "<option>\n";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  my $i        = 1;
  my $tax      = 0;
  my $taxaccno = "";
  foreach my $ref (@{ $form->{GL} }) {
    my $j = $i - 1;
    if ($tax && ($ref->{accno} eq $taxaccno)) {
      $form->{"tax_$j"}      = abs($ref->{amount});
      $form->{"taxchart_$j"} = $ref->{id} . "--" . $ref->{taxrate};
      if ($form->{taxincluded}) {
        if ($ref->{amount} < 0) {
          $form->{"debit_$j"} += $form->{"tax_$j"};
        } else {
          $form->{"credit_$j"} += $form->{"tax_$j"};
        }
      }
      $form->{"project_id_$j"} = $ref->{project_id};

    } else {
      $form->{"accno_$i"} = "$ref->{accno}--$ref->{tax_id}";
      for (qw(fx_transaction source memo)) { $form->{"${_}_$i"} = $ref->{$_} }
      if ($ref->{amount} < 0) {
        $form->{totaldebit} -= $ref->{amount};
        $form->{"debit_$i"} = $ref->{amount} * -1;
      } else {
        $form->{totalcredit} += $ref->{amount};
        $form->{"credit_$i"} = $ref->{amount};
      }
      $form->{"taxchart_$i"} = "0--0.00";
      $form->{"project_id_$i"} = $ref->{project_id};
      $i++;
    }
    if ($ref->{taxaccno} && !$tax) {
      $taxaccno = $ref->{taxaccno};
      $tax      = 1;
    } else {
      $taxaccno = "";
      $tax      = 0;
    }
  }

  $form->{rowcount} = $i;
  $form->{locked}   =
    ($form->datetonum($form->{transdate}, \%myconfig) <=
     $form->datetonum($form->{closedto}, \%myconfig));

  $main::lxdebug->leave_sub();
}

sub edit {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  prepare_transaction();

  $form->{title} = "Edit";

  $form->{show_details} = $myconfig{show_form_details} unless defined $form->{show_details};

  form_header();
  display_rows();
  form_footer();

  $main::lxdebug->leave_sub();
}


sub search {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  $form->{title} = $locale->text('Journal');

  $form->all_departments(\%myconfig);

  # departments
  if (@{ $form->{all_departments} || [] }) {
    $form->{selectdepartment} = "<option>\n";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  my $department = qq|
  	<tr>
	  <th align=right nowrap>| . $locale->text('Department') . qq|</th>
	  <td colspan=3><select name=department>$form->{selectdepartment}</select></td>
	</tr>
| if $form->{selectdepartment};

  $form->get_lists("projects" => { "key" => "ALL_PROJECTS",
                                   "all" => 1 });

  my %project_labels = ();
  my @project_values = ("");
  foreach my $item (@{ $form->{"ALL_PROJECTS"} }) {
    push(@project_values, $item->{"id"});
    $project_labels{$item->{"id"}} = $item->{"projectnumber"};
  }

  my $projectnumber =
    NTI($cgi->popup_menu('-name' => "project_id",
                         '-values' => \@project_values,
                         '-labels' => \%project_labels));

  # use JavaScript Calendar or not
  $form->{jsscript} = 1;
  my $jsscript = "";
  my ($button1, $button2, $onload);
  if ($form->{jsscript}) {

    # with JavaScript Calendar
    $button1 = qq|
       <td><input name=datefrom id=datefrom size=11 title="$myconfig{dateformat}" onBlur=\"check_right_date_format(this)\">
       <input type=button name=datefrom id="trigger1" value=|
      . $locale->text('button') . qq|></td>
       |;
    $button2 = qq|
       <td><input name=dateto id=dateto size=11 title="$myconfig{dateformat}" onBlur=\"check_right_date_format(this)\">
       <input type=button name=dateto id="trigger2" value=|
      . $locale->text('button') . qq|></td>
     |;

    #write Trigger
    $jsscript =
      Form->write_trigger(\%myconfig, "2", "datefrom", "BR", "trigger1",
                          "dateto", "BL", "trigger2");
  } else {

    # without JavaScript Calendar
    $button1 =
      qq|<td><input name=datefrom id=datefrom size=11 title="$myconfig{dateformat}" onBlur=\"check_right_date_format(this)\"></td>|;
    $button2 =
      qq|<td><input name=dateto id=dateto size=11 title="$myconfig{dateformat}" onBlur=\"check_right_date_format(this)\"></td>|;
  }
  $form->{javascript} .= qq|<script type="text/javascript" src="js/common.js"></script>|;
  $form->header;
  $onload = qq|focus()|;
  $onload .= qq|;setupDateFormat('|. $myconfig{dateformat} .qq|', '|. $locale->text("Falsches Datumsformat!") .qq|')|;
  $onload .= qq|;setupPoints('|. $myconfig{numberformat} .qq|', '|. $locale->text("wrongformat") .qq|')|;
  print qq|
<body onLoad="$onload">

<form method=post action=gl.pl>

<input type=hidden name=sort value=transdate>

<table width=100%>
  <tr>
    <th class=listtop>$form->{title}</th>
  </tr>
  <tr height="5"></tr>
  <tr>
    <td>
      <table>
	<tr>
	  <th align=right>| . $locale->text('Reference') . qq|</th>
	  <td><input name=reference size=20></td>
	  <th align=right>| . $locale->text('Source') . qq|</th>
	  <td><input name=source size=20></td>
	</tr>
	$department
	<tr>
	  <th align=right>| . $locale->text('Description') . qq|</th>
	  <td colspan=3><input name=description size=40></td>
	</tr>
	<tr>
	  <th align=right>| . $locale->text('Notes') . qq|</th>
	  <td colspan=3><input name=notes size=40></td>
	</tr>
	<tr>
	  <th align=right>| . $locale->text('Project Number') . qq|</th>
	  <td colspan=3>$projectnumber</td>
	</tr>
	<tr>
	  <th align=right>| . $locale->text('From') . qq|</th>
          $button1
	  <th align=right>| . $locale->text('To (time)') . qq|</th>
          $button2
	</tr>
	<tr>
	  <th align=right>| . $locale->text('Include in Report') . qq|</th>
	  <td colspan=3>
	    <table>
	      <tr>
		<td>
		  <input name="category" class=radio type=radio value=X checked>&nbsp;|
    . $locale->text('All') . qq|
		  <input name="category" class=radio type=radio value=A>&nbsp;|
    . $locale->text('Asset') . qq|
		  <input name="category" class=radio type=radio value=L>&nbsp;|
    . $locale->text('Liability') . qq|
		  <input name="category" class=radio type=radio value=I>&nbsp;|
    . $locale->text('Revenue') . qq|
		  <input name="category" class=radio type=radio value=E>&nbsp;|
    . $locale->text('Expense') . qq|
		</td>
	      </tr>
	      <tr>
		<table>
		  <tr>
		    <td align=right><input name="l_id" class=checkbox type=checkbox value=Y></td>
		    <td>| . $locale->text('ID') . qq|</td>
		    <td align=right><input name="l_transdate" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Date') . qq|</td>
		    <td align=right><input name="l_reference" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Reference') . qq|</td>
		    <td align=right><input name="l_description" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Description') . qq|</td>
		    <td align=right><input name="l_notes" class=checkbox type=checkbox value=Y></td>
		    <td>| . $locale->text('Notes') . qq|</td>
		  </tr>
		  <tr>
		    <td align=right><input name="l_debit" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Debit') . qq|</td>
		    <td align=right><input name="l_credit" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Credit') . qq|</td>
		    <td align=right><input name="l_source" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Source') . qq|</td>
		    <td align=right><input name="l_accno" class=checkbox type=checkbox value=Y checked></td>
		    <td>| . $locale->text('Account') . qq|</td>
		  </tr>
		  <tr>
		    <td align=right><input name="l_subtotal" class=checkbox type=checkbox value=Y></td>
		    <td>| . $locale->text('Subtotal') . qq|</td>
		    <td align=right><input name="l_projectnumbers" class=checkbox type=checkbox value=Y></td>
		    <td>| . $locale->text('Project Number') . qq|</td>
		  </tr>
		</table>
	      </tr>
	    </table>
	</tr>
      </table>
    </td>
  </tr>
  <tr>
    <td><hr size=3 noshade></td>
  </tr>
</table>

$jsscript

<input type=hidden name=nextsub value=generate_report>

<br>
<input class=submit type=submit name=action value="|
    . $locale->text('Continue') . qq|">
</form>

</body>
</html>
|;
  $main::lxdebug->leave_sub();
}

sub create_subtotal_row {
  $main::lxdebug->enter_sub();

  my ($totals, $columns, $column_alignment, $subtotal_columns, $class) = @_;

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $row = { map { $_ => { 'data' => '', 'class' => $class, 'align' => $column_alignment->{$_}, } } @{ $columns } };

  map { $row->{$_}->{data} = $form->format_amount(\%myconfig, $totals->{$_}, 2) } @{ $subtotal_columns };

  map { $totals->{$_} = 0 } @{ $subtotal_columns };

  $main::lxdebug->leave_sub();

  return $row;
}

sub generate_report {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  report_generator_set_default_sort('transdate', 1);

  GL->all_transactions(\%myconfig, \%$form);

  my %acctype = ('A' => $locale->text('Asset'),
                 'C' => $locale->text('Contra'),
                 'L' => $locale->text('Liability'),
                 'Q' => $locale->text('Equity'),
                 'I' => $locale->text('Revenue'),
                 'E' => $locale->text('Expense'),);

  $form->{title} = $locale->text('Journal');
  if ($form->{category} ne 'X') {
    $form->{title} .= " : " . $locale->text($acctype{ $form->{category} });
  }

  $form->{landscape} = 1;

  my $ml = ($form->{ml} =~ /(A|E|Q)/) ? -1 : 1;

  my @columns = qw(
    transdate      id               reference      description
    notes          source           debit          debit_accno
    credit         credit_accno     debit_tax      debit_tax_accno
    credit_tax     credit_tax_accno projectnumbers balance
  );

  my @hidden_variables = qw(accno source reference department description notes project_id datefrom dateto category l_subtotal previous_transdate);
  push @hidden_variables, map { "l_${_}" } @columns;

  my (@options, @date_options);
  push @options,      $locale->text('Account')     . " : $form->{accno} $form->{account_description}" if ($form->{accno});
  push @options,      $locale->text('Source')      . " : $form->{source}"                             if ($form->{source});
  push @options,      $locale->text('Reference')   . " : $form->{reference}"                          if ($form->{reference});
  push @options,      $locale->text('Description') . " : $form->{description}"                        if ($form->{description});
  push @options,      $locale->text('Notes')       . " : $form->{notes}"                              if ($form->{notes});

  push @date_options, $locale->text('From'), $locale->date(\%myconfig, $form->{datefrom}, 1)          if ($form->{datefrom});
  push @date_options, $locale->text('Bis'),  $locale->date(\%myconfig, $form->{dateto},   1)          if ($form->{dateto});
  push @options,      join(' ', @date_options)                                                        if (scalar @date_options);

  if ($form->{department}) {
    my ($department) = split /--/, $form->{department};
    push @options, $locale->text('Department') . " : $department";
  }


  my $callback = build_std_url('action=generate_report', grep { $form->{$_} } @hidden_variables);

  $form->{l_credit_accno}     = 'Y';
  $form->{l_debit_accno}      = 'Y';
  $form->{l_credit_tax}       = 'Y';
  $form->{l_debit_tax}        = 'Y';
  $form->{l_credit_tax_accno} = 'Y';
  $form->{l_debit_tax_accno}  = 'Y';
  $form->{l_balance}          = $form->{accno} ? 'Y' : '';

  my %column_defs = (
    'id'               => { 'text' => $locale->text('ID'), },
    'transdate'        => { 'text' => $locale->text('Date'), },
    'reference'        => { 'text' => $locale->text('Reference'), },
    'source'           => { 'text' => $locale->text('Source'), },
    'description'      => { 'text' => $locale->text('Description'), },
    'notes'            => { 'text' => $locale->text('Notes'), },
    'debit'            => { 'text' => $locale->text('Debit'), },
    'debit_accno'      => { 'text' => $locale->text('Debit Account'), },
    'credit'           => { 'text' => $locale->text('Credit'), },
    'credit_accno'     => { 'text' => $locale->text('Credit Account'), },
    'debit_tax'        => { 'text' => $locale->text('Debit Tax'), },
    'debit_tax_accno'  => { 'text' => $locale->text('Debit Tax Account'), },
    'credit_tax'       => { 'text' => $locale->text('Credit Tax'), },
    'credit_tax_accno' => { 'text' => $locale->text('Credit Tax Account'), },
    'balance'          => { 'text' => $locale->text('Balance'), },
    'projectnumbers'   => { 'text' => $locale->text('Project Numbers'), },
  );

  foreach my $name (qw(id transdate reference description debit_accno credit_accno debit_tax_accno credit_tax_accno)) {
    my $sortname                = $name =~ m/accno/ ? 'accno' : $name;
    my $sortdir                 = $sortname eq $form->{sort} ? 1 - $form->{sortdir} : $form->{sortdir};
    $column_defs{$name}->{link} = $callback . "&sort=$sortname&sortdir=$sortdir";
  }

  map { $column_defs{$_}->{visible} = $form->{"l_${_}"} ? 1 : 0 } @columns;
  map { $column_defs{$_}->{visible} = 0 } qw(debit_accno credit_accno debit_tax_accno credit_tax_accno) if $form->{accno};

  my %column_alignment;
  map { $column_alignment{$_}     = 'right'  } qw(balance id debit credit debit_tax credit_tax balance);
  map { $column_alignment{$_}     = 'center' } qw(reference debit_accno credit_accno debit_tax_accno credit_tax_accno);
  map { $column_alignment{$_}     = 'left' } qw(description source notes);
  map { $column_defs{$_}->{align} = $column_alignment{$_} } keys %column_alignment;

  my $report = SL::ReportGenerator->new(\%myconfig, $form);

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  $report->set_export_options('generate_report', @hidden_variables, qw(sort sortdir));

  $report->set_sort_indicator($form->{sort} eq 'accno' ? 'debit_accno' : $form->{sort}, $form->{sortdir});

  $report->set_options('top_info_text'        => join("\n", @options),
                       'output_format'        => 'HTML',
                       'title'                => $form->{title},
                       'attachment_basename'  => $locale->text('general_ledger_list') . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();

  # add sort to callback
  $form->{callback} = "$callback&sort=" . E($form->{sort}) . "&sortdir=" . E($form->{sortdir});


  my @totals_columns = qw(debit credit debit_tax credit_tax);
  my %subtotals      = map { $_ => 0 } @totals_columns;
  my %totals         = map { $_ => 0 } @totals_columns;
  my $idx            = 0;

  foreach my $ref (@{ $form->{GL} }) {

    my %rows;

    foreach my $key (qw(debit credit debit_tax credit_tax)) {
      $rows{$key} = [];
      foreach my $idx (sort keys(%{ $ref->{$key} })) {
        my $value         = $ref->{$key}->{$idx};
        $subtotals{$key} += $value;
        $totals{$key}    += $value;
        if ($key =~ /debit.*/) {
          $ml = -1;
        } else {
          $ml = 1;
        }
        $form->{balance}  = $form->{balance} + $value * $ml;
        push @{ $rows{$key} }, $form->format_amount(\%myconfig, $value, 2);
      }
    }

    foreach my $key (qw(debit_accno credit_accno debit_tax_accno credit_tax_accno ac_transdate source)) {
      my $col = $key eq 'ac_transdate' ? 'transdate' : $key;
      $rows{$col} = [ map { $ref->{$key}->{$_} } sort keys(%{ $ref->{$key} }) ];
    }

    my $row = { };
    map { $row->{$_} = { 'data' => '', 'align' => $column_alignment{$_} } } @columns;

    my $sh = "";
    if ($form->{balance} < 0) {
      $sh = " S";
      $ml = -1;
    } elsif ($form->{balance} > 0) {
      $sh = " H";
      $ml = 1;
    }
    my $data = $form->format_amount(\%myconfig, ($form->{balance} * $ml), 2);
    $data .= $sh;

    $row->{balance}->{data}        = $data;
    $row->{projectnumbers}->{data} = join ", ", sort { lc($a) cmp lc($b) } keys %{ $ref->{projectnumbers} };

    map { $row->{$_}->{data} = $ref->{$_} } qw(id reference description notes);

    map { $row->{$_}->{data} = \@{ $rows{$_} }; } qw(transdate debit credit debit_accno credit_accno debit_tax_accno credit_tax_accno source);

    foreach my $col (qw(debit_accno credit_accno debit_tax_accno credit_tax_accno)) {
      $row->{$col}->{link} = [ map { "${callback}&accno=" . E($_) } @{ $rows{$col} } ];
    }

    map { $row->{$_}->{data} = \@{ $rows{$_} } if ($ref->{"${_}_accno"} ne "") } qw(debit_tax credit_tax);

    $row->{reference}->{link} = build_std_url("script=$ref->{module}.pl", 'action=edit', 'id=' . E($ref->{id}), 'callback');

    my $row_set = [ $row ];

    if (($form->{l_subtotal} eq 'Y')
        && (($idx == (scalar @{ $form->{GL} } - 1))
            || ($ref->{ $form->{sort} } ne $form->{GL}->[$idx + 1]->{ $form->{sort} }))) {
      push @{ $row_set }, create_subtotal_row(\%subtotals, \@columns, \%column_alignment, [ qw(debit credit) ], 'listsubtotal');
    }

    $report->add_data($row_set);

    $idx++;
  }

  $report->add_separator();

  # = 0 for balanced ledger
  my $balanced_ledger = $totals{debit} + $totals{debit_tax} - $totals{credit} - $totals{credit_tax};

  my $row = create_subtotal_row(\%totals, \@columns, \%column_alignment, [ qw(debit credit debit_tax credit_tax) ], 'listtotal');

  my $sh = "";
  if ($form->{balance} < 0) {
    $sh = " S";
    $ml = -1;
  } elsif ($form->{balance} > 0) {
    $sh = " H";
    $ml = 1;
  }
  my $data = $form->format_amount(\%myconfig, ($form->{balance} * $ml), 2);
  $data .= $sh;

  $row->{balance}->{data}        = $data;

  $report->add_data($row);

  my $raw_bottom_info_text;

  if (!$form->{accno} && (abs($balanced_ledger) >  0.001)) {
    $raw_bottom_info_text .=
        '<p><span class="unbalanced_ledger">'
      . $locale->text('Unbalanced Ledger')
      . ': '
      . $form->format_amount(\%myconfig, $balanced_ledger, 3)
      . '</span></p> ';
  }

  $raw_bottom_info_text .= $form->parse_html_template('gl/generate_report_bottom');

  $report->set_options('raw_bottom_info_text' => $raw_bottom_info_text);

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub update {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->{oldtransdate} = $form->{transdate};

  my @a           = ();
  my $count       = 0;
  my $debittax    = 0;
  my $credittax   = 0;
  my $debitcount  = 0;
  my $creditcount = 0;
  my ($debitcredit, $amount);

  my @flds =
    qw(accno debit credit projectnumber fx_transaction source memo tax taxchart);

  for my $i (1 .. $form->{rowcount}) {

    unless (($form->{"debit_$i"} eq "") && ($form->{"credit_$i"} eq "")) {
      for (qw(debit credit tax)) {
        $form->{"${_}_$i"} =
          $form->parse_amount(\%myconfig, $form->{"${_}_$i"});
      }

      push @a, {};
      $debitcredit = ($form->{"debit_$i"} == 0) ? "0" : "1";
      if ($debitcredit) {
        $debitcount++;
      } else {
        $creditcount++;
      }

      if (($debitcount >= 2) && ($creditcount == 2)) {
        $form->{"credit_$i"} = 0;
        $form->{"tax_$i"}    = 0;
        $creditcount--;
        $creditlock = 1;
      }
      if (($creditcount >= 2) && ($debitcount == 2)) {
        $form->{"debit_$i"} = 0;
        $form->{"tax_$i"}   = 0;
        $debitcount--;
        $debitlock = 1;
      }
      if (($creditcount == 1) && ($debitcount == 2)) {
        $creditlock = 1;
      }
      if (($creditcount == 2) && ($debitcount == 1)) {
        $debitlock = 1;
      }
      if ($debitcredit && $credittax) {
        $form->{"taxchart_$i"} = "0--0.00";
      }
      if (!$debitcredit && $debittax) {
        $form->{"taxchart_$i"} = "0--0.00";
      }
      $amount =
        ($form->{"debit_$i"} == 0)
        ? $form->{"credit_$i"}
        : $form->{"debit_$i"};
      my $j = $#a;
      if (($debitcredit && $credittax) || (!$debitcredit && $debittax)) {
        $form->{"taxchart_$i"} = "0--0.00";
        $form->{"tax_$i"}      = 0;
      }
      my ($taxkey, $rate) = split(/--/, $form->{"taxchart_$i"});
      if ($taxkey > 1) {
        if ($debitcredit) {
          $debittax = 1;
        } else {
          $credittax = 1;
        }
        if ($form->{taxincluded}) {
          $form->{"tax_$i"} = $amount / ($rate + 1) * $rate;
        } else {
          $form->{"tax_$i"} = $amount * $rate;
        }
      } else {
        $form->{"tax_$i"} = 0;
      }

      for (@flds) { $a[$j]->{$_} = $form->{"${_}_$i"} }
      $count++;
    }
  }

  for my $i (1 .. $count) {
    my $j = $i - 1;
    for (@flds) { $form->{"${_}_$i"} = $a[$j]->{$_} }
  }

  for my $i ($count + 1 .. $form->{rowcount}) {
    for (@flds) { delete $form->{"${_}_$i"} }
  }

  $form->{rowcount} = $count + 1;

  &display_form;
  $main::lxdebug->leave_sub();

}

sub display_form {
  my ($init) = @_;
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  &form_header($init);

  #   for $i (1 .. $form->{rowcount}) {
  #     $form->{totaldebit} += $form->parse_amount(\%myconfig, $form->{"debit_$i"});
  #     $form->{totalcredit} += $form->parse_amount(\%myconfig, $form->{"credit_$i"});
  #
  #     &form_row($i);
  #   }
  &display_rows($init);
  &form_footer;
  $main::lxdebug->leave_sub();

}

sub display_rows {
  my ($init) = @_;
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $cgi      = $main::cgi;

  $form->{debit_1}     = 0 if !$form->{"debit_1"};
  $form->{totaldebit}  = 0;
  $form->{totalcredit} = 0;

  my %project_labels = ();
  my @project_values = ("");
  foreach my $item (@{ $form->{"ALL_PROJECTS"} }) {
    push(@project_values, $item->{"id"});
    $project_labels{$item->{"id"}} = $item->{"projectnumber"};
  }

  my %chart_labels = ();
  my @chart_values = ();
  my %charts = ();
  my $taxchart_init;
  foreach my $item (@{ $form->{ALL_CHARTS} }) {
    if ($item->{charttype} eq 'H'){ #falls �berschrift
      next;                         #�berspringen (Bug 1150)
    }
    my $key = $item->{accno} . "--" . $item->{tax_id};
    $taxchart_init = $item->{tax_id} unless (@chart_values);
    push(@chart_values, $key);
    $chart_labels{$key} = $item->{accno} . "--" . $item->{description};
    $charts{$item->{accno}} = $item;
  }

  my %taxchart_labels = ();
  my @taxchart_values = ();
  my %taxcharts = ();
  foreach my $item (@{ $form->{ALL_TAXCHARTS} }) {
    my $key = $item->{id} . "--" . $item->{rate};
    $taxchart_init = $key if ($taxchart_init == $item->{id});
    push(@taxchart_values, $key);
    $taxchart_labels{$key} = $item->{taxdescription} . " " . $item->{rate} * 100 . ' %';
    $taxcharts{$item->{id}} = $item;
  }

  my ($source, $memo, $source_hidden, $memo_hidden);
  for my $i (1 .. $form->{rowcount}) {
    if ($form->{show_details}) {
      $source = qq|
      <td><input name="source_$i" value="$form->{"source_$i"}" size="16"></td>|;
      $memo = qq|
      <td><input name="memo_$i" value="$form->{"memo_$i"}" size="16"></td>|;
    } else {
      $source_hidden = qq|
      <input type="hidden" name="source_$i" value="$form->{"source_$i"}" size="16">|;
      $memo_hidden = qq|
      <input type="hidden" name="memo_$i" value="$form->{"memo_$i"}" size="16">|;
    }

    my $selected_accno_full;
    my ($accno_row) = split(/--/, $form->{"accno_$i"});
    my $item = $charts{$accno_row};
    $selected_accno_full = "$item->{accno}--$item->{tax_id}";

    my $selected_taxchart = $form->{"taxchart_$i"};
    my ($selected_accno, $selected_tax_id) = split(/--/, $selected_accno_full);
    my ($previous_accno, $previous_tax_id) = split(/--/, $form->{"previous_accno_$i"});

    if ($previous_accno &&
        ($previous_accno eq $selected_accno) &&
        ($previous_tax_id ne $selected_tax_id)) {
      my $item = $taxcharts{$selected_tax_id};
      $selected_taxchart = "$item->{id}--$item->{rate}";
    }

    $selected_accno      = '' if ($init);
    $selected_taxchart ||= $taxchart_init;

    my $accno = qq|<td>| .
      NTI($cgi->popup_menu('-name' => "accno_$i",
                           '-id' => "accno_$i",
                           '-onChange' => "setTaxkey($i)",
                           '-style' => 'width:200px',
                           '-values' => \@chart_values,
                           '-labels' => \%chart_labels,
                           '-default' => $selected_accno_full))
      . $cgi->hidden('-name' => "previous_accno_$i",
                     '-default' => $selected_accno_full)
      . qq|</td>|;
    $tax = qq|<td>| .
      NTI($cgi->popup_menu('-name' => "taxchart_$i",
                           '-id' => "taxchart_$i",
                           '-style' => 'width:200px',
                           '-values' => \@taxchart_values,
                           '-labels' => \%taxchart_labels,
                           '-default' => $selected_taxchart))
      . qq|</td>|;

    my ($fx_transaction, $checked);
    if ($init) {
      if ($form->{transfer}) {
        $fx_transaction = qq|
        <td><input name="fx_transaction_$i" class=checkbox type=checkbox value=1></td>
    |;
      }

    } else {
      if ($form->{"debit_$i"} != 0) {
        $form->{totaldebit} += $form->{"debit_$i"};
        if (!$form->{taxincluded}) {
          $form->{totaldebit} += $form->{"tax_$i"};
        }
      } else {
        $form->{totalcredit} += $form->{"credit_$i"};
        if (!$form->{taxincluded}) {
          $form->{totalcredit} += $form->{"tax_$i"};
        }
      }

      for (qw(debit credit tax)) {
        $form->{"${_}_$i"} =
          ($form->{"${_}_$i"})
          ? $form->format_amount(\%myconfig, $form->{"${_}_$i"}, 2)
          : "";
      }

      if ($i < $form->{rowcount}) {
        if ($form->{transfer}) {
          $checked = ($form->{"fx_transaction_$i"}) ? "1" : "";
          my $x = ($checked) ? "x" : "";
          $fx_transaction = qq|
      <td><input type=hidden name="fx_transaction_$i" value="$checked">$x</td>
    |;
        }
        $form->hide_form("accno_$i");

      } else {
        if ($form->{transfer}) {
          $fx_transaction = qq|
      <td><input name="fx_transaction_$i" class=checkbox type=checkbox value=1></td>
    |;
        }
      }
    }
    my $debitreadonly  = "";
    my $creditreadonly = "";
    if ($i == $form->{rowcount}) {
      if ($debitlock) {
        $debitreadonly = "readonly";
      } elsif ($creditlock) {
        $creditreadonly = "readonly";
      }
    }

    my $projectnumber =
      NTI($cgi->popup_menu('-name' => "project_id_$i",
                           '-values' => \@project_values,
                           '-labels' => \%project_labels,
                           '-default' => $form->{"project_id_$i"} ));

    my $copy2credit = 'onkeyup="copy_debit_to_credit()"' if $i == 1;

    print qq|<tr valign=top>
    $accno
    <td id="chart_balance_$i" align="right">&nbsp;</td>
    $fx_transaction
    <td><input name="debit_$i" size="8" value="$form->{"debit_$i"}" accesskey=$i $copy2credit $debitreadonly></td>
    <td><input name="credit_$i" size=8 value="$form->{"credit_$i"}" $creditreadonly></td>
    <td><input type="hidden" name="tax_$i" value="$form->{"tax_$i"}">$form->{"tax_$i"}</td>
    $tax|;

    if ($form->{show_details}) {
      print qq|
    $source
    $memo
    <td>$projectnumber</td>
|;
    }
    print qq|
    $source_hidden
    $memo_hidden
  </tr>
|;
  }

  $form->hide_form(qw(rowcount selectaccno));

  $main::lxdebug->leave_sub();

}

sub form_header {
  my ($init) = @_;
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;


  my @old_project_ids = ();
  map({ push(@old_project_ids, $form->{"project_id_$_"})
          if ($form->{"project_id_$_"}); } (1..$form->{"rowcount"}));

  $form->get_lists("projects"  => { "key"       => "ALL_PROJECTS",
                                    "all"       => 0,
                                    "old_id"    => \@old_project_ids },
                   "charts"    => { "key"       => "ALL_CHARTS",
                                    "transdate" => $form->{transdate} },
                   "taxcharts" => "ALL_TAXCHARTS");

  GL->get_chart_balances('charts' => $form->{ALL_CHARTS});

  my $title      = $form->{title};
  $form->{title} = $locale->text("$title General Ledger Transaction");
  my $readonly   = ($form->{id}) ? "readonly" : "";

  my $show_details_checked = "checked" if $form->{show_details};

  my $ob_transaction_checked = "checked" if $form->{ob_transaction};
  my $cb_transaction_checked = "checked" if $form->{cb_transaction};

  # $locale->text('Add General Ledger Transaction')
  # $locale->text('Edit General Ledger Transaction')

  map { $form->{$_} =~ s/\"/&quot;/g }
    qw(reference description chart taxchart);

  $form->{javascript} = qq|<script type="text/javascript">
  <!--
  function setTaxkey(row) {
    var accno  = document.getElementById('accno_' + row);
    var taxkey = accno.options[accno.selectedIndex].value;
    var reg = /--([0-9]*)/;
    var found = reg.exec(taxkey);
    var index = found[1];
    index = parseInt(index);
    var tax = 'taxchart_' + row;
    for (var i = 0; i < document.getElementById(tax).options.length; ++i) {
      var reg2 = new RegExp("^"+ index, "");
      if (reg2.exec(document.getElementById(tax).options[i].value)) {
        document.getElementById(tax).options[i].selected = true;
        break;
      }
    }
  };

  function copy_debit_to_credit() {
    var txt = document.getElementsByName('debit_1')[0].value;
    document.getElementsByName('credit_2')[0].value = txt;
  };
  //-->
  </script>
  <script type="text/javascript" src="js/show_form_details.js"></script>
  <script type="text/javascript" src="js/jquery.js"></script>
|;

  $form->{selectdepartment} =~ s/ selected//;
  $form->{selectdepartment} =~
    s/option>\Q$form->{department}\E/option selected>$form->{department}/;

  my $description;
  if ((my $rows = $form->numtextrows($form->{description}, 50)) > 1) {
    $description =
      qq|<textarea name=description rows=$rows cols=50 wrap=soft $readonly >$form->{description}</textarea>|;
  } else {
    $description =
      qq|<input name=description size=50 value="$form->{description}" $readonly>|;
  }

  my $taxincluded = ($form->{taxincluded}) ? "checked" : "";

  if ($init) {
    $taxincluded = "checked";
  }

  my $department;
  $department = qq|
  	<tr>
	  <th align=right nowrap>| . $locale->text('Department') . qq|</th>
	  <td colspan=3><select name=department>$form->{selectdepartment}</select></td>
	  <input type=hidden name=selectdepartment value="$form->{selectdepartment}">
	</tr>
| if $form->{selectdepartment};
  if ($init) {
    $form->{fokus} = "gl.reference";
  } else {
    $form->{fokus} = qq|gl.accno_$form->{rowcount}|;
  }

  my $gldatefixedmonth = ($form->{gldatefixedmonth}) ? "checked" : "";
  if ($init) { $gldatefixedmonth = "checked"; }


  # use JavaScript Calendar or not
  $form->{jsscript} = 1;
  my $jsscript = "";
  my ($button1, $button2);
  if ($form->{jsscript}) {

    # with JavaScript Calendar
    $button1 = qq|
       <td><input name=transdate id=transdate size=11 title="$myconfig{dateformat}" value="$form->{transdate}" $readonly onBlur=\"check_right_date_format(this)\">
       <input type=button name=transdate id="trigger1" value=|
      . $locale->text('button') . qq|>                 Monat/Jahr festhalten: <input type="checkbox" name="gldatefixedmonth" $gldatefixedmonth /> 
 </td>
       |;

    #write Trigger
    $jsscript =
      Form->write_trigger(\%myconfig, "1", "transdate", "BL", "trigger1");
  } else {

    # without JavaScript Calendar
    $button1 =
      qq|<td><input name=transdate id=transdate size=11 title="$myconfig{dateformat}" value="$form->{transdate}" $readonly onBlur=\"check_right_date_format(this)\">                Monat/Jahr festhalten: <input type="checkbox" name="gldatefixedmonth"   $gldatefixedmonth /> 
</td>|;
  }

  $form->{previous_id}     ||= "--";
  $form->{previous_gldate} ||= "--";
  $form->{previous_transdate} ||= "-o-";

  $jsscript .= $form->parse_html_template('gl/form_header_chart_balances_js');

  $form->header;




  print qq|
<body onLoad="focus()">

<script type="text/javascript" src="js/follow_up.js"></script>


<form method=post name="gl" action=gl.pl>
|;

  $form->hide_form(qw(id closedto locked storno storno_id previous_id previous_gldate previous_transdate));

  print qq|
<input type=hidden name=title value="$title">

<input type="hidden" name="follow_up_trans_id_1" value="| . H($form->{id}) . qq|">
<input type="hidden" name="follow_up_trans_type_1" value="gl_transaction">
<input type="hidden" name="follow_up_trans_info_1" value="| . H($form->{id}) . qq|">
<input type="hidden" name="follow_up_rowcount" value="1">

<table width=100%>
  <tr>
    <th class=listtop>$form->{title}</th>
  </tr>
  <tr height="5"></tr>
  <tr>
    <td>
      <table width=100%>
        <tr>
          <td colspan="6" align="left">|
    . $locale->text("Previous transnumber text")
    . " $form->{previous_id} [vom $form->{previous_transdate}] "
    . $locale->text("Previous transdate text")
    . " $form->{previous_gldate}"
    . qq|</td>
        </tr>
	<tr>
	  <th align=right>| . $locale->text('Reference') . qq|</th>
	  <td><input name=reference size=20 value="$form->{reference}" $readonly></td>
	  <td align=left>
	    <table>
	      <tr>
		<th align=right nowrap>| . $locale->text('Date') . qq|</th>
                $button1
	      </tr>
	    </table>
	  </td>
	</tr>|;
  if ($form->{id}) {
    print qq|
	<tr>
	  <th align=right>| . $locale->text('Belegnummer') . qq|</th>
	  <td><input name=id size=20 value="$form->{id}" $readonly></td>
	  <td align=left>
	  <table>
	      <tr>
		<th align=right width=50%>| . $locale->text('Buchungsdatum') . qq|</th>
		<td align=left><input name=gldate size=11 title="$myconfig{dateformat}" value=$form->{gldate} $readonly onBlur=\"check_right_date_format(this)\">
                </td>
	      </tr>
	    </table>
	  </td>
	</tr>|;
  }
  print qq|
	$department|;
  if ($form->{id}) {
    print qq|
	<tr>
	  <th align=right width=1%>| . $locale->text('Description') . qq|</th>
	  <td width=1%>$description</td>
          <td>
	    <table>
	      <tr>
		<th align=left>| . $locale->text('MwSt. inkl.') . qq|</th>
		<td><input type=checkbox name=taxincluded value=1 $taxincluded></td>
	      </tr>
	    </table>
	 </td>
	  <td align=left>
	    <table width=100%>
	      <tr>
		<th align=right width=50%>| . $locale->text('Mitarbeiter') . qq|</th>
		<td align=left><input name=employee size=20  value="| . H($form->{employee}) . qq|" readonly></td>
	      </tr>
	    </table>
	  </td>
	</tr>|;
  } else {
    print qq|
	<tr>
	  <th align=left width=1%>| . $locale->text('Description') . qq|</th>
	  <td width=1%>$description</td>
	  <td>
	    <table>
	      <tr>
		<th align=left>| . $locale->text('MwSt. inkl.') . qq|</th>
		<td><input type=checkbox name=taxincluded value=1 $taxincluded></td>
	      </tr>
	    </table>
	 </td>
	</tr>|;
  }

  print qq|
      <tr>
      <tr><td colspan=4><table><tr>
       <td>
        | . $locale->text('OB Transaction') . qq|<input type="checkbox" name="ob_transaction" value="1" $ob_transaction_checked>
       </td>
       <td>
        | . $locale->text('CB Transaction') . qq|<input type="checkbox" name="cb_transaction" value="1" $cb_transaction_checked>
       </td>
      </tr></table></td></tr>
      <tr>
       <td width="1%" align="right" nowrap>| . $locale->text('Show details') . qq|</td>
       <td width="1%"><input type="checkbox" onclick="show_form_details();" name="show_details" value="1" $show_details_checked></td>
      </tr>|;

  print qq|
      <tr>
      <td colspan=4>
          <table width=100%>
	   <tr class=listheading>
	  <th class=listheading style="width:15%">|
    . $locale->text('Account') . qq|</th>
	  <th class=listheading style="width:10%">| . $locale->text('Chart balance') . qq|</th>
	  <th class=listheading style="width:10%">|
    . $locale->text('Debit') . qq|</th>
	  <th class=listheading style="width:10%">|
    . $locale->text('Credit') . qq|</th>
          <th class=listheading style="width:10%">|
    . $locale->text('Tax') . qq|</th>
          <th class=listheading style="width:5%">|
    . $locale->text('Taxkey') . qq|</th>|;

  if ($form->{show_details}) {
    print qq|
	  <th class=listheading style="width:20%">| . $locale->text('Source') . qq|</th>
	  <th class=listheading style="width:20%">| . $locale->text('Memo') . qq|</th>
	  <th class=listheading style="width:20%">| . $locale->text('Project Number') . qq|</th>
|;
  }

  print qq|
	</tr>

$jsscript
|;
  $main::lxdebug->leave_sub();

}

sub form_footer {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my $follow_ups_block;
  if ($form->{id}) {
    my $follow_ups = FU->follow_ups('trans_id' => $form->{id});

    if (@{ $follow_ups} ) {
      my $num_due       = sum map { $_->{due} * 1 } @{ $follow_ups };
      $follow_ups_block = qq|<p>| . $locale->text("There are #1 unfinished follow-ups of which #2 are due.", scalar @{ $follow_ups }, $num_due) . qq|</p>|;
    }
  }

  my ($dec) = ($form->{totaldebit} =~ /\.(\d+)/);
  $dec = length $dec;
  my $decimalplaces = ($dec > 2) ? $dec : 2;
  my $radieren = ($form->current_date(\%myconfig) eq $form->{gldate}) ? 1 : 0;

  map {
    $form->{$_} = $form->format_amount(\%myconfig, $form->{$_}, 2, "&nbsp;")
  } qw(totaldebit totalcredit);

  print qq|
    <tr class=listtotal>
    <th colspan="3" align=right class=listtotal> $form->{totaldebit}</th>
    <th align=right class=listtotal> $form->{totalcredit}</th>
    <td colspan=6></td>
    </tr>
  </table>
  </td>
  </tr>
</table>

<input name=callback type=hidden value="$form->{callback}">

$follow_ups_block

<br>
|;


  my $transdate = $form->datetonum($form->{transdate}, \%myconfig);
  my $closedto  = $form->datetonum($form->{closedto},  \%myconfig);

  if ($form->{id}) {

    if (!$form->{storno}) {
      print qq|<input class=submit type=submit name=action value="| . $locale->text('Storno') . qq|">|;
    }

    # L�schen und �ndern von Buchungen nicht mehr m�glich (GoB) nur am selben Tag m�glich
    if (!$form->{locked} && $radieren) {
      print qq|
        <input class=submit type=submit name=action value="| . $locale->text('Post') . qq|" accesskey="b">
        <input class=submit type=submit name=action value="| . $locale->text('Delete') . qq|">|;
    }

    print qq|
        <input class=submit type=submit name=action id=update_button value="| . $locale->text('Update') . qq|">
        <input type="button" class="submit" onclick="follow_up_window()" value="|
      . $locale->text('Follow-Up')
      . qq|"> |;

  } else {
    if ($form->{draft_id}) {
      my $remove_draft_checked = 'checked' if ($form->{remove_draft});
      print qq|<p>\n|
        . qq|  <input name="remove_draft" id="remove_draft" type="checkbox" class="checkbox" ${remove_draft_checked}>|
        . qq|  <label for="remove_draft">| . $locale->text('Remove Draft') . qq|</label>\n|
        . qq|</p>\n|;
    }

    print qq|
        <input class=submit type=submit name=action id=update_button value="| . $locale->text('Update') . qq|">
        <input class=submit type=submit name=action value="| . $locale->text('Post') . qq|"> |
        . NTI($cgi->submit('-name' => 'action', '-value' => $locale->text('Save draft'), '-class' => 'submit'))
        . $cgi->hidden('-name' => 'draft_id',          '-default' => [$form->{draft_id}])
        . $cgi->hidden('-name' => 'draft_description', '-default' => [$form->{draft_description}]);
  }

  print "
  </form>

</body>
</html>
";
  $main::lxdebug->leave_sub();

}

sub delete {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  $form->header;

  print qq|
<body>

<form method=post action=gl.pl>
|;

  map { $form->{$_} =~ s/\"/&quot;/g } qw(reference description);

  delete $form->{header};

  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    print qq|<input type="hidden" name="$key" value="$form->{$key}">\n|;
  }

  print qq|
<h2 class=confirm>| . $locale->text('Confirm!') . qq|</h2>

<h4>|
    . $locale->text('Are you sure you want to delete Transaction')
    . qq| $form->{reference}</h4>

<input name=action class=submit type=submit value="|
    . $locale->text('Yes') . qq|">
</form>
|;
  $main::lxdebug->leave_sub();

}

sub yes {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if (GL->delete_transaction(\%myconfig, \%$form)){
    # saving the history
      if(!exists $form->{addition} && $form->{id} ne "") {
        $form->{snumbers} = qq|ordnumber_| . $form->{ordnumber};
  	    $form->{addition} = "DELETED";
  	    $form->save_history($form->dbconnect(\%myconfig));
      }
    # /saving the history
    $form->redirect($locale->text('Transaction deleted!'))
  }
  $form->error($locale->text('Cannot delete transaction!'));
  $main::lxdebug->leave_sub();

}

sub post_transaction {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  # check if there is something in reference and date
  $form->isblank("reference",   $locale->text('Reference missing!'));
  $form->isblank("transdate",   $locale->text('Transaction Date missing!'));
  $form->isblank("description", $locale->text('Description missing!'));


  my $transdate = $form->datetonum($form->{transdate}, \%myconfig);
  if ($form->{previous_transdate}) {
      my $previousdate = $form->datetonum($form->{previous_transdate}, \%myconfig);

      if ($form->{gldatefixedmonth}) {
	  if (not substr($transdate, 0, 6) eq substr($previousdate, 0, 6)) {
	      $form->error("Datum $transdate nicht im gleichen Monat wie $previousdate (und das war das Datum der vorhergehenden Buchung)");
	  }	  
      }
  }



  my $closedto  = $form->datetonum($form->{closedto},  \%myconfig);

  my @a           = ();
  my $count       = 0;
  my $debittax    = 0;
  my $credittax   = 0;
  my $debitcount  = 0;
  my $creditcount = 0;
  my $debitcredit;

  my @flds = qw(accno debit credit projectnumber fx_transaction source memo tax taxchart);

  for my $i (1 .. $form->{rowcount}) {
    next if $form->{"debit_$i"} eq "" && $form->{"credit_$i"} eq "";

    for (qw(debit credit tax)) {
      $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"});
    }

    push @a, {};
    $debitcredit = ($form->{"debit_$i"} == 0) ? "0" : "1";

    if ($debitcredit) {
      $debitcount++;
    } else {
      $creditcount++;
    }

    if (($debitcount >= 2) && ($creditcount == 2)) {
      $form->{"credit_$i"} = 0;
      $form->{"tax_$i"}    = 0;
      $creditcount--;
      $creditlock = 1;
    }
    if (($creditcount >= 2) && ($debitcount == 2)) {
      $form->{"debit_$i"} = 0;
      $form->{"tax_$i"}   = 0;
      $debitcount--;
      $debitlock = 1;
    }
    if (($creditcount == 1) && ($debitcount == 2)) {
      $creditlock = 1;
    }
    if (($creditcount == 2) && ($debitcount == 1)) {
      $debitlock = 1;
    }
    if ($debitcredit && $credittax) {
      $form->{"taxchart_$i"} = "0--0.00";
    }
    if (!$debitcredit && $debittax) {
      $form->{"taxchart_$i"} = "0--0.00";
    }
    my $amount = ($form->{"debit_$i"} == 0)
            ? $form->{"credit_$i"}
            : $form->{"debit_$i"};
    my $j = $#a;
    if (($debitcredit && $credittax) || (!$debitcredit && $debittax)) {
      $form->{"taxchart_$i"} = "0--0.00";
      $form->{"tax_$i"}      = 0;
    }
    my ($taxkey, $rate) = split(/--/, $form->{"taxchart_$i"});
    if ($taxkey > 1) {
      if ($debitcredit) {
        $debittax = 1;
      } else {
        $credittax = 1;
      }
      if ($form->{taxincluded}) {
        $form->{"tax_$i"} = $amount / ($rate + 1) * $rate;
        if ($debitcredit) {
          $form->{"debit_$i"} = $form->{"debit_$i"} - $form->{"tax_$i"};
        } else {
          $form->{"credit_$i"} = $form->{"credit_$i"} - $form->{"tax_$i"};
        }
      } else {
        $form->{"tax_$i"} = $amount * $rate;
      }
    } else {
      $form->{"tax_$i"} = 0;
    }

    for (@flds) { $a[$j]->{$_} = $form->{"${_}_$i"} }
    $count++;
  }

  for my $i (1 .. $count) {
    my $j = $i - 1;
    for (@flds) { $form->{"${_}_$i"} = $a[$j]->{$_} }
  }

  for my $i ($count + 1 .. $form->{rowcount}) {
    for (@flds) { delete $form->{"${_}_$i"} }
  }

  my ($debit, $credit, $taxtotal);
  for my $i (1 .. $form->{rowcount}) {
    my $dr  = $form->{"debit_$i"};
    my $cr  = $form->{"credit_$i"};
    $tax = $form->{"tax_$i"};
    if ($dr && $cr) {
      $form->error($locale->text('Cannot post transaction with a debit and credit entry for the same account!'));
    }
    $debit    += $dr + $tax if $dr;
    $credit   += $cr + $tax if $cr;
    $taxtotal += $tax if $form->{taxincluded}
  }

  $form->{taxincluded} = 0 if !$taxtotal;

  # this is just for the wise guys
  $form->error($locale->text('Cannot post transaction for a closed period!'))
    if ($form->date_closed($form->{"transdate"}, \%myconfig));
  if ($form->round_amount($debit, 2) != $form->round_amount($credit, 2)) {
    $form->error($locale->text('Out of balance transaction!'));
  }

  if ($form->round_amount($debit, 2) + $form->round_amount($credit, 2) == 0) {
    $form->error($locale->text('Empty transaction!'));
  }

  if ((my $errno = GL->post_transaction(\%myconfig, \%$form)) <= -1) {
    $errno *= -1;
    my @err;
    $err[1] = $locale->text('Cannot have a value in both Debit and Credit!');
    $err[2] = $locale->text('Debit and credit out of balance!');
    $err[3] = $locale->text('Cannot post a transaction without a value!');

    $form->error($err[$errno]);
  }
  undef($form->{callback});
  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = qq|ordnumber_| . $form->{ordnumber};
    $form->{addition} = "SAVED";
    $form->{what_done} = $locale->text("Buchungsnummer") . " = " . $form->{id};
    $form->save_history($form->dbconnect(\%myconfig));
  }
  # /saving the history

  $main::lxdebug->leave_sub();
}

sub post {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my $locale   = $main::locale;

  $form->{title}  = $locale->text("$form->{title} General Ledger Transaction");
  $form->{storno} = 0;

  post_transaction();

  remove_draft() if $form->{remove_draft};

  $form->{callback} = build_std_url("action=add", "show_details");
  $form->redirect($form->{callback});

  $main::lxdebug->leave_sub();
}

sub post_as_new {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  $form->{id} = 0;
  &add;
  $main::lxdebug->leave_sub();

}

sub storno {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  # don't cancel cancelled transactions
  if (IS->has_storno(\%myconfig, $form, 'gl')) {
    $form->{title} = $locale->text("Cancel Accounts Receivables Transaction");
    $form->error($locale->text("Transaction has already been cancelled!"));
  }

  GL->storno($form, \%myconfig, $form->{id});

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = "ordnumber_$form->{ordnumber}";
    $form->{addition} = "STORNO";
    $form->save_history($form->dbconnect(\%myconfig));
  }
  # /saving the history

  $form->redirect(sprintf $locale->text("Transaction %d cancelled."), $form->{storno_id});

  $main::lxdebug->leave_sub();
}

sub continue {
  call_sub($main::form->{nextsub});
}

1;
