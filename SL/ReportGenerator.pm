package SL::ReportGenerator;

use IO::Wrap;
use List::Util qw(max);
use Text::CSV_XS;

use SL::Form;

sub new {
  my $type = shift;

  my $self = { };

  $self->{myconfig} = shift;
  $self->{form}     = shift;

  $self->{data}     = [];
  $self->{options}  = {
    'std_column_visibility' => 0,
    'output_format'         => 'HTML',
    'allow_pdf_export'      => 1,
    'allow_csv_export'      => 1,
    'pdf_export'            => {
      'paper_size'          => 'A4',
      'orientation'         => 'landscape',
      'font_size'           => '10',
      'margin_top'          => 1.5,
      'margin_left'         => 1.5,
      'margin_bottom'       => 1.5,
      'margin_right'        => 1.5,
      'number'              => 1,
      'print'               => 0,
      'printer_id'          => 0,
      'copies'              => 1,
    },
    'csv_export'            => {
      'quote_char'          => '"',
      'sep_char'            => ';',
      'escape_char'         => '"',
      'eol_style'           => 'DOS',
      'headers'             => 1,
    },
  };
  $self->{export}   = {
    'nextsub'       => '',
    'variable_list' => '',
  };

  $self->set_options(@_) if (@_);

  return bless $self, $type;
}

sub set_columns {
  my $self    = shift;
  my %columns = @_;

  $self->{columns} = \%columns;

  foreach my $column (values %{ $self->{columns} }) {
    $column->{visible} = $self->{options}->{std_column_visibility} unless defined $column->{visible};
  }

  $self->set_column_order(sort keys %{ $self->{columns} });
}

sub set_column_order {
  my $self    = shift;

  my $order   = 0;
  my %columns = map { $order++; ($_, $order) } @_;

  foreach my $column (sort keys %{ $self->{columns} }) {
    next if $columns{$column};

    $order++;
    $columns{$column} = $order;
  }

  $self->{column_order} = [ sort { $columns{$a} <=> $columns{$b} } keys %columns ];
}

sub set_sort_indicator {
  my $self = shift;

  $self->{options}->{sort_indicator_column}    = shift;
  $self->{options}->{sort_indicator_direction} = shift;
}

sub add_data {
  my $self = shift;

  my $last_row_set;

  while (my $arg = shift) {
    if ('ARRAY' eq ref $arg) {
      push @{ $self->{data} }, $arg;
      $last_row_set = $arg;

    } elsif ('HASH' eq ref $arg) {
      my $row_set = [ $arg ];
      push @{ $self->{data} }, $row_set;
      $last_row_set = $row_set;

    } else {
      $self->{form}->error('Incorrect usage -- expecting hash or array ref');
    }
  }

  return $last_row_set;
}

sub add_separator {
  my $self = shift;

  push @{ $self->{data} }, { 'type' => 'separator' };
}

sub clear_data {
  my $self = shift;

  $self->{data} = [];
}

sub set_options {
  my $self    = shift;
  my %options = @_;

  map { $self->{options}->{$_} = $options{$_} } keys %options;
}

sub set_options_from_form {
  my $self     = shift;

  my $form     = $self->{form};
  my $myconfig = $self->{myconfig};

  foreach my $key (qw(output_format)) {
    my $full_key = "report_generator_${key}";
    $self->{options}->{$key} = $form->{$full_key} if (defined $form->{$full_key});
  }

  foreach my $format (qw(pdf csv)) {
    my $opts = $self->{options}->{"${format}_export"};
    foreach my $key (keys %{ $opts }) {
      my $full_key = "report_generator_${format}_options_${key}";
      $opts->{$key} = $key =~ /^margin/ ? $form->parse_amount($myconfig, $form->{$full_key}) : $form->{$full_key};
    }
  }
}

sub set_export_options {
  my $self        = shift;

  $self->{export} = {
    'nextsub'       => shift,
    'variable_list' => join(" ", @_),
  };
}

sub generate_with_headers {
  my $self   = shift;
  my $format = lc $self->{options}->{output_format};

  if (!$self->{columns}) {
    $self->{form}->error('Incorrect usage -- no columns specified');
  }

  my $filename =  $self->{options}->{attachment_basename} || 'report';
  $filename    =~ s|.*\\||;
  $filename    =~ s|.*/||;

  if ($format eq 'html') {
    $self->{form}->{title} = $self->{title};
    $self->{form}->header();
    print $self->generate_html_content();

  } elsif ($format eq 'csv') {
    print qq|content-type: text/csv\n|;
    print qq|content-disposition: attachment; filename=${filename}.csv\n\n|;
    $self->generate_csv_content();

  } elsif ($format eq 'pdf') {
    $self->generate_pdf_content();

  } else {
    $self->{form}->error('Incorrect usage -- unknown format (supported are HTML, CSV, PDF)');
  }
}

sub get_visible_columns {
  my $self   = shift;
  my $format = shift;

  return grep { my $c = $self->{columns}->{$_}; $c && $c->{visible} && (($c->{visible} == 1) || ($c->{visible} =~ /${format}/i)) } @{ $self->{column_order} };
}

sub html_format {
  my $self  = shift;
  my $value = shift;

  $value =  $self->{form}->quote_html($value);
  $value =~ s/\r//g;
  $value =~ s/\n/<br>/g;

  return $value;
}

sub prepare_html_content {
  my $self = shift;

  my ($column, $name, @column_headers);

  my $opts            = $self->{options};
  my @visible_columns = $self->get_visible_columns('HTML');

  foreach $name (@visible_columns) {
    $column = $self->{columns}->{$name};

    my $header = {
      'name'                     => $name,
      'link'                     => $column->{link},
      'text'                     => $column->{text},
      'show_sort_indicator'      => $name eq $opts->{sort_indicator_column},
      'sort_indicator_direction' => $opts->{sort_indicator_direction},
    };

    push @column_headers, $header;
  }

  my ($outer_idx, $inner_idx) = (0, 0);
  my @rows;

  foreach my $row_set (@{ $self->{data} }) {
    if ('HASH' eq ref $row_set) {
      my $row_data = {
        'IS_CONTROL'    => 1,
        'IS_SEPARATOR'  => $row_set->{type} eq 'separator',
        'NUM_COLUMNS'   => scalar @visible_columns,
      };

      push @rows, $row_data;

      next;
    }

    $outer_idx++;

    foreach my $row (@{ $row_set }) {
      $inner_idx++;

      map { $row->{$_}->{data} = $self->html_format($row->{$_}->{data}) } @visible_columns;

      my $row_data = {
        'COLUMNS'       => [ map { $row->{$_} } @visible_columns ],
        'outer_idx'     => $outer_idx,
        'outer_idx_odd' => $outer_idx % 2,
        'inner_idx'     => $inner_idx,
      };

      push @rows, $row_data;
    }
  }

  my @export_variables;
  foreach my $key (split m/ +/, $self->{export}->{variable_list}) {
    push @export_variables, { 'key' => $key, 'value' => $self->{form}->{$key} };
  }

  my $allow_pdf_export = $opts->{allow_pdf_export} && (-x $main::html2ps_bin) && (-x $main::ghostscript_bin);

  my $variables = {
    'TITLE'                => $opts->{title},
    'TOP_INFO_TEXT'        => $self->html_format($opts->{top_info_text}),
    'RAW_TOP_INFO_TEXT'    => $opts->{raw_top_info_text},
    'BOTTOM_INFO_TEXT'     => $self->html_format($opts->{bottom_info_text}),
    'RAW_BOTTOM_INFO_TEXT' => $opts->{raw_bottom_info_text},
    'ALLOW_PDF_EXPORT'     => $allow_pdf_export,
    'ALLOW_CSV_EXPORT'     => $opts->{allow_csv_export},
    'SHOW_EXPORT_BUTTONS'  => $allow_pdf_export || $opts->{allow_csv_export},
    'COLUMN_HEADERS'       => \@column_headers,
    'NUM_COLUMNS'          => scalar @column_headers,
    'ROWS'                 => \@rows,
    'EXPORT_VARIABLES'     => \@export_variables,
    'EXPORT_VARIABLE_LIST' => $self->{export}->{variable_list},
    'EXPORT_NEXTSUB'       => $self->{export}->{nextsub},
  };

  return $variables;
}

sub generate_html_content {
  my $self      = shift;
  my $variables = $self->prepare_html_content();

  return $self->{form}->parse_html_template('report_generator/html_report', $variables);
}

sub verify_paper_size {
  my $self                 = shift;
  my $requested_paper_size = lc shift;
  my $default_paper_size   = shift;

  my %allowed_paper_sizes  = map { $_ => 1 } qw(a3 a4 letter legal);

  return $allowed_paper_sizes{$requested_paper_size} ? $requested_paper_size : $default_paper_size;
}

sub generate_pdf_content {
  my $self      = shift;
  my $variables = $self->prepare_html_content();
  my $form      = $self->{form};
  my $myconfig  = $self->{myconfig};
  my $opt       = $self->{options}->{pdf_export};

  my $opt_number     = $opt->{number}                     ? 'number : 1'    : '';
  my $opt_landscape  = $opt->{orientation} eq 'landscape' ? 'landscape : 1' : '';

  my $opt_paper_size = $self->verify_paper_size($opt->{paper_size}, 'a4');

  my $html2ps_config = <<"END"
\@html2ps {
  option {
    titlepage: 0;
    hyphenate: 0;
    colour: 1;
    ${opt_landscape};
    ${opt_number};
  }
  paper {
    type: ${opt_paper_size};
  }
  break-table: 1;
}

\@page {
  margin-top:    $opt->{margin_top}cm;
  margin-left:   $opt->{margin_left}cm;
  margin-bottom: $opt->{margin_bottom}cm;
  margin-right:  $opt->{margin_right}cm;
}

BODY {
  font-family: Helvetica;
  font-size:   $opt->{font_size}pt;
}

END
  ;

  my $printer_command;
  if ($opt->{print} && $opt->{printer_id}) {
    $form->{printer_id} = $opt->{printer_id};
    $form->get_printer_code($myconfig);
    $printer_command = $form->{printer_command};
  }

  my $cfg_file_name = Common::tmpname() . '-html2ps-config';
  my $cfg_file      = IO::File->new($cfg_file_name, 'w') || $form->error($locale->text('Could not write the html2ps config file.'));

  $cfg_file->print($html2ps_config);
  $cfg_file->close();

  my $html_file_name = Common::tmpname() . '.html';
  my $html_file      = IO::File->new($html_file_name, 'w');

  if (!$html_file) {
    unlink $cfg_file_name;
    $form->error($locale->text('Could not write the temporary HTML file.'));
  }

  $html_file->print($form->parse_html_template('report_generator/pdf_report', $variables));
  $html_file->close();

  my $cmdline =
    "\"${main::html2ps_bin}\" -f \"${cfg_file_name}\" \"${html_file_name}\" | " .
    "\"${main::ghostscript_bin}\" -q -dSAFER -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sPAPERSIZE=${opt_paper_size} -sOutputFile=- -c .setpdfwrite -";

  my $gs = IO::File->new("${cmdline} |");
  if ($gs) {
    my $content;

    if (!$printer_command) {
      print qq|content-type: application/pdf\n|;
      print qq|content-disposition: attachment; filename=${filename}.pdf\n\n|;

      while (my $line = <$gs>) {
        print $line;
      }

    } else {
      while (my $line = <$gs>) {
        $content .= $line;
      }
    }

    $gs->close();
    unlink $cfg_file_name, $html_file_name;

    if ($printer_command && $content) {
      foreach my $i (1 .. max $opt->{copies}, 1) {
        my $printer = IO::File->new("| ${printer_command}");
        if (!$printer) {
          $form->error($locale->text('Could not spawn the printer command.'));
        }
        $printer->print($content);
        $printer->close();
      }

      $form->{report_generator_printed} = 1;
    }

  } else {
    unlink $cfg_file_name, $html_file_name;
    $form->error($locale->text('Could not spawn html2ps or GhostScript.'));
  }
}

sub generate_csv_content {
  my $self = shift;

  my %valid_sep_chars    = (';' => ';', ',' => ',', ':' => ':', 'TAB' => "\t");
  my %valid_escape_chars = ('"' => 1, "'" => 1);
  my %valid_quote_chars  = ('"' => 1, "'" => 1);

  my $opts        = $self->{options}->{csv_export};
  my $eol         = $opts->{eol_style} eq 'DOS'               ? "\r\n"                              : "\n";
  my $sep_char    = $valid_sep_chars{$opts->{sep_char}}       ? $valid_sep_chars{$opts->{sep_char}} : ';';
  my $escape_char = $valid_escape_chars{$opts->{escape_char}} ? $opts->{escape_char}                : '"';
  my $quote_char  = $valid_quote_chars{$opts->{quote_char}}   ? $opts->{quote_char}                 : '"';

  $escape_char    = $quote_char if ($opts->{escape_char} eq 'QUOTE_CHAR');

  my $csv = Text::CSV_XS->new({ 'binary'      => 1,
                                'sep_char'    => $sep_char,
                                'escape_char' => $escape_char,
                                'quote_char'  => $quote_char,
                                'eol'         => $eol, });

  my $stdout          = wraphandle(\*STDOUT);
  my @visible_columns = $self->get_visible_columns('CSV');

  if ($opts->{headers}) {
    $csv->print($stdout, [ map { $self->{columns}->{$_}->{text} } @visible_columns ]);
  }

  foreach my $row_set (@{ $self->{data} }) {
    next if ('ARRAY' ne ref $row_set);
    foreach my $row (@{ $row_set }) {
      $csv->print($stdout, [ map { $row->{$_}->{data} } @visible_columns ]);
    }
  }
}

1;