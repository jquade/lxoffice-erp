#!/usr/bin/perl -w
=head1 NAME

find-use

=head1 EXAMPLE

 ~/ledgersmb # utils/devel/find-use
 0.000000 : HTML::Entities
 0.000000 : Locale::Maketext::Lexicon
 0.000000 : Module::Build
 ...

=head1 EXPLINATION

This util is useful for package builders to identify all the CPAN dependencies we've made.  It required Module::CoreList (which is core, but is not yet in any stable
release of perl)  to determine if a module is distributed with perl or not.  The output reports which version of perl the module is in.  If it reports 0.000000, then the
module is not in core perl, and needs to be installed before Lx-Office will operate.

=head1 AUTHOR

http://www.ledgersmb.org/ - The LedgerSMB team

=head1 LICENSE

Distributed under the terms of the GNU General Public License v2.
=cut


use strict;
use warnings;

open GREP, "grep -r '^use ' . |";
use Module::CoreList;

my %uselines;
while(<GREP>) { 
	next if /SL::/;
	next if /LX::/;
	next if /use warnings/;
	next if /use strict/;
	next if /use vars/;
	chomp;
	my ($file, $useline) = m/^([^:]+):use\s(.*?)$/;
	$uselines{$useline}||=[];
	push @{$uselines{$useline}}, $file;
}

my %modules;
foreach my $useline (keys %uselines) {

	my ($module) = grep { $_ } $useline =~ /(?:base ['"]([a-z:]+)|([a-z:]+)(?:\s|;))/i;
	my $version = Module::CoreList->first_release($module);
	$modules{$module} = $version||0;
}

foreach my $mod (sort { $modules{$a} == 0 ? -1 : $modules{$b} == 0 ? 1 : 0  or $a cmp $b } keys %modules) { 
	printf "%2.6f : %s\n", $modules{$mod}, $mod;
}

