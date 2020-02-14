#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use autodie;

use File::Basename;
use Cwd qw(abs_path);
use Git::Wrapper; # libgit-wrapper-perl (?)

my $root = defined($ENV{MDVL_CI_PHOENIX_ROOT})? $ENV{MDVL_CI_PHOENIX_ROOT}:
						abs_path(dirname($0)."/..");
print "Git  Doc  Bui  Cle  Onl  Upd  Repository\n";
opendir(my $dir, $root);
my @entries;
while(my $entry = readdir($dir)) {
	next if(not(-d "$root/$entry") or $entry =~ m/^(x-|\.|[lwb]r-)/);
	push @entries, $entry;
}
closedir($dir);
@entries = sort @entries;
for my $entry (@entries) {
	my $isgit = (-d "$root/$entry/.git");
	my $isdoc = (-f "$root/$entry/README.md");
	my $isbuild = (-f "$root/$entry/build.xml");
	my $isonl = 0;
	my $isclean = 0;
	my $isupdated = 0;
	if($isgit) {
		my $git = Git::Wrapper->new("$root/$entry");
		$isclean = not $git->status->is_dirty;
		my @remotes = $git->remote();
		if((scalar @remotes) ne 0) {
			$isonl = 1;
			my @log_regular = $git->log;
			my @log_origin = $git->log({ remotes => "origin" });
			$isupdated = ((scalar @log_regular) eq
							(scalar @log_origin));
		}
	}
	my @status_b = ($isgit, $isdoc, $isbuild, $isclean, $isonl, $isupdated);
	my @status_w = map { $_? "\033[1;32mYES\033[0m":
					"\033[1;31mNO=\033[0m" } @status_b;
	for my $s (@status_w) {
		print $s;
		print "  ";
	}
	print "$entry\n";
}
