#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use autodie;

use File::Basename;
use Cwd qw(abs_path);
use Git::Wrapper; # libgit-wrapper-perl (?)

# $_[0]: file to check
sub count_todo_markers {
	my $file_to_check = shift;
	my $ntodo = 0;
	open my $fh, "<:encoding(UTF-8)", $file_to_check;
	# https://stackoverflow.com/questions/17693699
	0 <= index $_, "TODO" and $ntodo++ while <$fh>;
	close $fh;
	return $ntodo;
}

my $root = defined($ENV{MDVL_CI_PHOENIX_ROOT})? $ENV{MDVL_CI_PHOENIX_ROOT}:
						abs_path(dirname($0)."/..");
print "Git  Doc  Bui  Cle  Onl  Upd  NTO  Repository\n";
opendir(my $dir, $root);
my @entries;
while(my $entry = readdir($dir)) {
	next if(not(-d "$root/$entry") or $entry =~ m/^(x-|\.|[lwb]r-)/);
	push @entries, $entry;
}
closedir($dir);
@entries = sort @entries;
for my $entry (@entries) {
	my $readme    = "$root/$entry/README.md";
	my $buildxml  = "$root/$entry/build.xml";
	my $isgit     = (-d "$root/$entry/.git");
	my $isdoc     = (-f $readme);
	my $isbuild   = (-f $buildxml);
	my $isonl     = 0;
	my $isclean   = 0;
	my $isupdated = 0;
	my $ntodo     = ($isdoc?   count_todo_markers($readme):   0) +
			($isbuild? count_todo_markers($buildxml): 0);
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
	my @status_imp = (1,    0,      0,        1,        1,      1);
	my @status_w = ();

	for(my $i = 0; $i <= $#status_b; $i++) {
		if($status_b[$i]) {
			push @status_w, "\033[1;32mYES\033[0m";
		} elsif($status_imp[$i]) {
			push @status_w, "\033[1;31mNO=\033[0m";
		} else {
			push @status_w, "\033[1;33mNO=\033[0m";
		}
	}
	push @status_w, ($ntodo == 0)?  "\033[1;32m00\033[0m":
				sprintf("\033[1;31m%02d\033[0m", $ntodo);
	for my $s (@status_w) {
		print $s;
		print "  ";
	}
	print "$entry\n";
}
