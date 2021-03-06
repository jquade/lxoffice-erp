#!/usr/bin/perl

# -n do not include custom_ scripts
# -v verbose mode, shows progress stuff

# this version of locles processes not only all required .pl files
# but also all parse_html_templated files.

use Data::Dumper;
use FileHandle;
use Getopt::Long;
use List::Util qw(first);
use POSIX;
use Pod::Usage;

$| = 1;

$basedir  = "../..";
$bindir   = "$basedir/bin/mozilla";
$dbupdir  = "$basedir/sql/Pg-upgrade";
$dbupdir2 = "$basedir/sql/Pg-upgrade2";
$menufile = "menu.ini";
$submitsearch = qr/type\s*=\s*[\"\']?submit/i;

%referenced_html_files = ();

my $opt_v = 0;
my $opt_n = 0;
my $opt_c = 0;

sub parse_args {
  my ($help, $man);

  GetOptions('no-custom-files' => \$opt_n,
             'check-files'     => \$opt_c,
             'verbose'         => \$opt_v,
             'help'            => \$help,
             'man'             => \$man,);

  if ($help) {
    pod2usage(1);
    exit 0;
  }

  if ($man) {
    pod2usage(-exitstatus => 0, -verbose => 2);
    exit 0;
  }
}

parse_args();

opendir DIR, "$bindir" or die "$!";
@progfiles = grep { /\.pl$/ && !/(_|^\.)/ } readdir DIR;
seekdir DIR, 0;
@customfiles = grep /_/, readdir DIR;
closedir DIR;

# put customized files into @customfiles

if ($opt_n) {
  @customfiles = ();
  @menufiles   = ($menufile);
} else {
  opendir DIR, "$basedir" or die "$!";
  @menufiles = grep { /.*?_$menufile$/ } readdir DIR;
  closedir DIR;
  unshift @menufiles, $menufile;
}

opendir DIR, $dbupdir or die "$!";
@dbplfiles = grep { /\.pl$/ } readdir DIR;
closedir DIR;

opendir DIR, $dbupdir2 or die "$!";
@dbplfiles2 = grep { /\.pl$/ } readdir DIR;
closedir DIR;

# slurp the translations in
if (-f 'all') {
  require "all";
}

my %old_texts = %{ $self->{texts} };

# Read HTML templates.
#%htmllocale = ();
#@htmltemplates = <../../templates/webpages/*/*_master.html>;
#foreach $file (@htmltemplates) {
#  scanhtmlfile($file);
#}

map({ handle_file($_, $bindir); } @progfiles);
map({ handle_file($_, $dbupdir); } @dbplfiles);
map({ handle_file($_, $dbupdir2); } @dbplfiles2);

sub handle_file {
  my ($file, $dir) = @_;
  print "\n$file" if $opt_v;
  %locale = ();
  %submit = ();
  %subrt  = ();

  &scanfile("$dir/$file");

  # scan custom_{module}.pl or {login}_{module}.pl files
  foreach $customfile (@customfiles) {
    if ($customfile =~ /_$file/) {
      if (-f "$dir/$customfile") {
        &scanfile("$dir/$customfile");
      }
    }
  }

  # if this is the menu.pl file
  if ($file eq 'menu.pl') {
    foreach $item (@menufiles) {
      &scanmenu("$basedir/$item");
    }
  }

  if ($file eq 'menunew.pl') {
    foreach $item (@menufiles) {
      &scanmenu("$basedir/$item");
      print "." if $opt_v;
    }
  }

  $file =~ s/\.pl//;

  eval { require 'missing'; };
  unlink 'missing';

  foreach $text (keys %$missing) {
    if ($locale{$text} || $htmllocale{$text}) {
      unless ($self->{texts}{$text}) {
        $self->{texts}{$text} = $missing->{$text};
      }
    }
  }

  open FH, ">$file" or die "$! : $file";

  print FH q|#!/usr/bin/perl

$self->{texts} = {
|;

  foreach $key (sort keys %locale) {
    if ($self->{texts}{$key}) {
      $text = $self->{texts}{$key};
    } else {
      $text = $key;
    }
    $text =~ s/'/\\'/g;
    $text =~ s/\\$/\\\\/;

    $keytext = $key;
    $keytext =~ s/'/\\'/g;
    $keytext =~ s/\\$/\\\\/;

    print FH qq|  '$keytext'|
      . (' ' x (27 - length($keytext)))
      . qq| => '$text',\n|;
  }

  print FH q|};

$self->{subs} = {
|;

  foreach $key (sort keys %subrt) {
    $text = $key;
    $text =~ s/'/\\'/g;
    $text =~ s/\\$/\\\\/;
    print FH qq|  '$text'| . (' ' x (27 - length($text))) . qq| => '$text',\n|;
  }

  foreach $key (sort keys %submit) {
    $text = ($self->{texts}{$key}) ? $self->{texts}{$key} : $key;
    $text =~ s/'/\\'/g;
    $text =~ s/\\$/\\\\/;

    $english_sub = $key;
    $english_sub =~ s/'/\\'/g;
    $english_sub =~ s/\\$/\\\\/;
    $english_sub = lc $key;

    $translated_sub = lc $text;
    $english_sub    =~ s/( |-|,)/_/g;
    $translated_sub =~ s/( |-|,)/_/g;
    print FH qq|  '$translated_sub'|
      . (' ' x (27 - length($translated_sub)))
      . qq| => '$english_sub',\n|;
  }

  print FH q|};

1;
|;

  close FH;

}

#foreach $file (@htmltemplates) {
#  converthtmlfile($file);
#}

# now print out all

open FH, ">all" or die "$! : all";

print FH q|#!/usr/bin/perl

# These are all the texts to build the translations files.
# The file has the form of 'english text'  => 'foreign text',
# you can add the translation in this file or in the 'missing' file
# run locales.pl from this directory to rebuild the translation files

$self->{texts} = {
|;

foreach $key (sort keys %alllocales) {
  $text = $self->{texts}{$key};

  $count++;

  $text =~ s/'/\\'/g;
  $text =~ s/\\$/\\\\/;
  $key  =~ s/'/\\'/g;
  $key  =~ s/\\$/\\\\/;

  unless ($text) {
    $notext++;
    push @missing, $key;
  }

  print FH qq|  '$key'| . (' ' x (27 - length($key))) . qq| => '$text',\n|;

}

print FH q|};

1;
|;

close FH;

if (@missing) {
  open FH, ">missing" or die "$! : missing";

  print FH q|#!/usr/bin/perl

# add the missing texts and run locales.pl to rebuild

$missing = {
|;

  foreach $text (@missing) {
    print FH qq|  '$text'| . (' ' x (27 - length($text))) . qq| => '',\n|;
  }

  print FH q|};

1;
|;

  close FH;

}

@lost = ();

if (-f "lost") {
  require "lost";
  unlink "lost";
}

while (($text, $translation) = each %old_texts) {
  next if ($alllocales{$text});

  push @lost, { 'text' => $text, 'translation' => $translation };
}

if (scalar @lost) {
  splice @lost, 0, (scalar @lost - 50) if (scalar @lost > 50);

  open FH, ">lost";
  print FH "#!/usr/bin/perl\n\n" .
    "# The last 50 texts that have been removed.\n" .
    "# This file will be auto-generated by locales.pl. Do not edit it.\n\n" .
    "\@lost = (\n";

  foreach $entry (@lost) {
    $entry->{text}        =~ s/\'/\\\'/g;
    $entry->{translation} =~ s/\'/\\\'/g;
    print FH "  { 'text' => '$entry->{text}', 'translation' => '$entry->{translation}' },\n";
  }

  print FH ");\n\n1;\n";
  close FH;
}

open(FH, "LANGUAGE");
@language = <FH>;
close(FH);
$trlanguage = $language[0];
chomp $trlanguage;

if ($opt_c) {
  search_unused_htmlfiles();
  search_translated_htmlfiles_wo_master();
}

$per = sprintf("%.1f", ($count - $notext) / $count * 100);
print "\n$trlanguage - ${per}%";
print " - $notext/$count missing" if $notext;
print "\n";

exit;

# eom

sub extract_text_between_parenthesis {
  my ($fh, $line) = @_;
  my ($inside_string, $pos, $text, $quote_next) = (undef, 0, "", 0);

  while (1) {
    if (length($line) <= $pos) {
      $line = <$fh>;
      return ($text, "") unless ($line);
      $pos = 0;
    }

    my $cur_char = substr($line, $pos, 1);

    if (!$inside_string) {
      if ((length($line) >= ($pos + 3)) && (substr($line, $pos, 2)) eq "qq") {
        $inside_string = substr($line, $pos + 2, 1);
        $pos += 2;

      } elsif ((length($line) >= ($pos + 2)) &&
               (substr($line, $pos, 1) eq "q")) {
        $inside_string = substr($line, $pos + 1, 1);
        $pos++;

      } elsif (($cur_char eq '"') || ($cur_char eq '\'')) {
        $inside_string = $cur_char;

      } elsif (($cur_char eq ")") || ($cur_char eq ',')) {
        return ($text, substr($line, $pos + 1));
      }

    } else {
      if ($quote_next) {
        $text .= $cur_char;
        $quote_next = 0;

      } elsif ($cur_char eq '\\') {
        $text .= $cur_char;
        $quote_next = 1;

      } elsif ($cur_char eq $inside_string) {
        undef($inside_string);

      } else {
        $text .= $cur_char;

      }
    }
    $pos++;
  }
}

sub scanfile {
  my $file = shift;
  my $dont_include_subs = shift;
  my $scanned_files = shift;

  # sanitize file
  $file =~ s=/+=/=g;

  $scanned_files = {} unless ($scanned_files);
  return if ($scanned_files->{$file});
  $scanned_files->{$file} = 1;

  if (!defined $cached{$file}) {

    return unless (-f "$file");

    my $fh = new FileHandle;
    open $fh, "$file" or die "$! : $file";

    my ($is_submit, $line_no, $sub_line_no) = (0, 0, 0);

    while (<$fh>) {
      $line_no++;

      # is this another file
      if (/require\s+\W.*\.pl/) {
        my $newfile = $&;
        $newfile =~ s/require\s+\W//;
        $newfile =~ s|bin/mozilla||;
#         &scanfile("$bindir/$newfile", 0, $scanned_files);
         $cached{$file}{scan}{"$bindir/$newfile"} = 1;
      } elsif (/use\s+SL::(.*?);/) {
        my $module =  $1;
        $module    =~ s|::|/|g;
#         &scanfile("../../SL/${1}.pm", 1, $scanned_files);
        $cached{$file}{scannosubs}{"../../SL/${module}.pm"} = 1;
      }

      # is this a template call?
      if (/parse_html_template2?\s*\(\s*[\"\']([\w\/]+)\s*[\"\']/) {
        my $newfile = "$basedir/templates/webpages/$1_master.html";
        if (/parse_html_template2/) {
          print "E: " . strip_base($file) . " is still using 'parse_html_template2' for " . strip_base($newfile) . ".\n";
        }
        if (-f $newfile) {
#           &scanhtmlfile($newfile);
#           &converthtmlfile($newfile);
           $cached{$file}{scanh}{$newfile} = 1;
          print "." if $opt_v;
        } elsif ($opt_c) {
          print "W: missing HTML template: " . strip_base($newfile) . " (referenced from " . strip_base($file) . ")\n";
        }
      }

      # is this a sub ?
      if (/^sub /) {
        next if ($dont_include_subs);
        ($null, $subrt) = split / +/;
#        $subrt{$subrt} = 1;
        $cached{$file}{subr}{$subrt} = 1;
        next;
      }

      my $rc = 1;

      while ($rc) {
        if (/Locale/) {
          unless (/^use /) {
            my ($null, $country) = split /,/;
            $country =~ s/^ +[\"\']//;
            $country =~ s/[\"\'].*//;
          }
        }

        my $postmatch = "";

        # is it a submit button before $locale->
        if (/$submitsearch/) {
          $postmatch = "$'";
          if ($` !~ /locale->text/) {
            $is_submit   = 1;
            $sub_line_no = $line_no;
          }
        }

        my ($found) = /locale->text.*?\(/;
        my $postmatch = "$'";

        if ($found) {
          my $string;
          ($string, $_) = extract_text_between_parenthesis($fh, $postmatch);
          $postmatch = $_;

          # if there is no $ in the string record it
          unless (($string =~ /\$\D.*/) || ("" eq $string)) {

            # this guarantees one instance of string
#            $locale{$string} = 1;
            $cached{$file}{locale}{$string} = 1;

            # this one is for all the locales
#            $alllocales{$string} = 1;
            $cached{$file}{all}{$string} = 1;

            # is it a submit button before $locale->
            if ($is_submit) {
#              $submit{$string} = 1;
              $cached{$file}{submit}{$string} = 1;
            }
          }
        } elsif ($postmatch =~ />/) {
          $is_submit = 0;
        }

        # exit loop if there are no more locales on this line
        ($rc) = ($postmatch =~ /locale->text/);

        if (   ($postmatch =~ />/)
            || (!$found && ($sub_line_no != $line_no) && />/)) {
          $is_submit = 0;
        }
      }
    }

    close($fh);

  }

  map { $alllocales{$_} = 1 }   keys %{$cached{$file}{all}};
  map { $locale{$_} = 1 }       keys %{$cached{$file}{locale}};
  map { $submit{$_} = 1 }       keys %{$cached{$file}{submit}};
  map { $subrt{$_} = 1 }        keys %{$cached{$file}{subr}};
  map { &scanfile($_, 0, $scanned_files) } keys %{$cached{$file}{scan}};
  map { &scanfile($_, 1, $scanned_files) } keys %{$cached{$file}{scannosubs}};
  map { &scanhtmlfile($_)  }    keys %{$cached{$file}{scanh}};

  @referenced_html_files{keys %{$cached{$file}{scanh}}} = (1) x scalar keys %{$cached{$file}{scanh}};
}

sub scanmenu {
  my $file = shift;

  my $fh = new FileHandle;
  open $fh, "$file" or die "$! : $file";

  my @a = grep m/^\[/, <$fh>;
  close($fh);

  # strip []
  grep { s/(\[|\])//g } @a;

  foreach my $item (@a) {
    @b = split /--/, $item;
    foreach $string (@b) {
      chomp $string;
      $locale{$string}     = 1;
      $alllocales{$string} = 1;
    }
  }

}

sub scanhtmlfile {
  local *IN;

  if (!defined $cached{$_[0]}) {
    my %plugins = ( 'loaded' => { }, 'needed' => { } );

    open(IN, $_[0]) || die $_[0];

    my $copying = 0;
    my $issubmit = 0;
    my $text = "";
    while (my $line = <IN>) {
      chomp($line);

      while ($line =~ m/\[\%[^\w]*use[^\w]+(\w+)[^\w]*?\%\]/gi) {
        $plugins{loaded}->{$1} = 1;
      }

      while ($line =~ m/\[\%[^\w]*(\w+)\.\w+\(/g) {
        my $plugin = $1;
        $plugins{needed}->{$plugin} = 1 if (first { $_ eq $plugin } qw(HTML LxERP JavaScript MultiColumnIterator));
      }

      while ("" ne $line) {
        if (!$copying) {
          if ($line =~ m|<translate>|i) {
            my $eom = $+[0];
            if ($` =~ /$submitsearch/) {
              $issubmit = 1
            }
            substr($line, 0, $eom) = "";
            $copying = 1;
          } else {
            $line = "";
          }

        } else {
          if ($line =~ m|</translate>|i) {
            $text .= $`;
            substr($line, 0, $+[0]) = "";
            $text =~ s/\s+/ /g;

            $copying = 0;
            if ($issubmit) {
  #            $submit{$text} = 1;
               $cached{$_[0]}{submit}{$text} = 1;
              $issubmit = 0;
            }
  #          $alllocales{$text} = 1;
             $cached{$_[0]}{all}{$text} = 1;
  #          $htmllocale{$text} = 1;
             $cached{$_[0]}{html}{$text} = 1;
            $text = "";

          } else {
            $text .= $line;
            $line = "";
          }
        }
      }
    }

    close(IN);

    foreach my $plugin (keys %{ $plugins{needed} }) {
      next if ($plugins{loaded}->{$plugin});
      print "E: " . strip_base($_[0]) . " requires the Template plugin '$plugin', but is not loaded with '[\% USE $plugin \%]'.\n";
    }

    &converthtmlfile($_[0]);
  }

  # copy back into global arrays
  map { $alllocales{$_} = 1 }  keys %{$cached{$_[0]}{all}};
  map { $htmllocales{$_} = 1 } keys %{$cached{$_[0]}{html}};
  map { $submit{$_} = 1 }      keys %{$cached{$_[0]}{submit}};
}

sub converthtmlfile {
  local *IN;
  local *OUT;

  my $file = shift;

  open(IN, $file) || die;

  my $langcode = (split("/", getcwd()))[-1];
  $file =~ s/_master.html$/_${langcode}.html/;

  open(OUT, ">$file") || die;

  my $copying = 0;
  my $text = "";
  while (my $line = <IN>) {
    chomp($line);
    if ("" eq $line) {
      print(OUT "\n");
      next;
    }

    while ("" ne $line) {
      if (!$copying) {
        if ($line =~ m|<translate>|i) {
          print(OUT $`);
          substr($line, 0, $+[0]) = "";
          $copying = 1;
          print(OUT "\n") if ("" eq $line);

        } else {
          print(OUT "${line}\n");
          $line = "";
        }

      } else {
        if ($line =~ m|</translate>|i) {
          $text .= $`;
          substr($line, 0, $+[0]) = "";
          $text =~ s/\s+/ /g;
          $copying = 0;
          $alllocales{$text} = 1;
          $htmllocale{$text} = 1;
          print(OUT $self->{"texts"}{$text} || $text);
          print(OUT "\n") if ("" eq $line);
          $text = "";

        } else {
          $text .= $line;
          $line = "";
        }
      }
    }
  }

  close(IN);
  close(OUT);
}

sub search_unused_htmlfiles {
  my @unscanned_dirs = ('../../templates/webpages');

  while (scalar @unscanned_dirs) {
    my $dir = shift @unscanned_dirs;

    foreach my $entry (<$dir/*>) {
      if (-d $entry) {
        push @unscanned_dirs, $entry;

      } elsif (($entry =~ /_master.html$/) && -f $entry && !$referenced_html_files{$entry}) {
        print "W: unused HTML template: " . strip_base($entry) . "\n";

      }
    }
  }
}

sub search_translated_htmlfiles_wo_master {
  my @unscanned_dirs = ('../../templates/webpages');

  while (scalar @unscanned_dirs) {
    my $dir = shift @unscanned_dirs;

    foreach my $entry (<$dir/*>) {
      if (-d $entry) {
        push @unscanned_dirs, $entry;

      } elsif (($entry =~ /_[a-z]+\.html$/) && ($entry !~ /_master.html$/) && -f $entry) {
        my $master =  $entry;
        $master    =~ s/[a-z]+\.html$/master.html/;
        if (! -f $master) {
          print "W: translated HTML template without master: " . strip_base($entry) . "\n";
        }
      }
    }
  }
}

sub strip_base {
  my $s =  "$_[0]";             # Create a copy of the string.

  $s    =~ s|^../../||;
  $s    =~ s|templates/webpages/||;

  return $s;
}

__END__

=head1 NAME

locales.pl - Collect strings for translation in Lx-Office

=head1 SYNOPSIS

locales.pl [options]

 Options:
  -n, --no-custom-files  Do not process files whose name contains "_"
  -c, --check-files      Run extended checks on HTML files
  -v, --verbose          Be more verbose
  -h, --help             Show this help

=head1 OPTIONS

=over 8

=item B<-n>, B<--no-custom-files>

Do not process files whose name contains "_", e.g. "custom_io.pl".

=item B<-c>, B<--check-files>

Run extended checks on the usage of templates. This can be used to
discover HTML templates that are never used as well as the usage of
non-existing HTML templates.

=item B<-v>, B<--verbose>

Be more verbose.

=back

=head1 DESCRIPTION

This script collects strings from Perl files, the menu.ini file and
HTML templates and puts them into the file "all" for translation.  It
also distributes those translations back to the individual files.

=cut
