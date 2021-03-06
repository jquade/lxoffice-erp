#!/usr/bin/perl
#
######################################################################
# SQL-Ledger Accounting
# Copyright (C) 2001
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#  Contributors:
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
#######################################################################
#
# this script sets up the terminal and runs the scripts
# in bin/$terminal directory
# admin.pl is linked to this script
#
#######################################################################

use strict;

BEGIN {
  unshift @INC, "modules/override"; # Use our own versions of various modules (e.g. YAML).
  push    @INC, "modules/fallback"; # Only use our own versions of modules if there's no system version.
}

# setup defaults, DO NOT CHANGE
$main::userspath  = "users";
$main::templates  = "templates";
$main::memberfile = "users/members";
$main::sendmail   = "| /usr/sbin/sendmail -t";
########## end ###########################################

$| = 1;

use SL::LXDebug;
$main::lxdebug = LXDebug->new();

eval { require "config/lx-erp.conf"; };
eval { require "config/lx-erp-local.conf"; } if -f "config/lx-erp-local.conf";

if ($ENV{CONTENT_LENGTH}) {
  read(STDIN, $_, $ENV{CONTENT_LENGTH});
}

if ($ENV{QUERY_STRING}) {
  $_ = $ENV{QUERY_STRING};
}

if ($ARGV[0]) {
  $_ = $ARGV[0];
}

my %form = split /[&=]/;

# fix for apache 2.0 bug
map { $form{$_} =~ s/\\$// } keys %form;

# name of this script
$0 =~ tr/\\/\//;
my $pos = rindex $0, '/';
my $script = substr($0, $pos + 1);

$form{login} =~ s|.*/||;

if (-e "$main::userspath/nologin" && $script ne 'admin.pl') {
  print "content-type: text/plain

Login disabled!\n";

  exit;
}

require "bin/mozilla/installationcheck.pl";
verify_installation();

$ARGV[0] = "$_&script=$script";
require "bin/mozilla/$script";

# end of main

