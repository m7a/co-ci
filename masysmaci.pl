#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use autodie;

use File::Basename;
use Cwd qw(abs_path);
use XML::DOM; # libxml-dom-perl
use Git::Wrapper; # libgit-wrapper-perl (?)

use Data::Dumper 'Dumper'; # debug only

my $root = abs_path(dirname($0)."/..");

# Next features
# [ ] Benennung vereinheitlichen für Konfiguration
# [ ] repo management (create, add, update, remove) is separate
# [ ] run environments
#     default: local command execution
#     option:  ssh command execution (configure ssh data in config XML)
#     <runenv name="" type="ssh" host="..." port="..." user="">ID_RSA</runenv>
#     <runenv name="" type="ansible" 
#     such an xml version is possibly not the best, because how do we spearate
#     an i386 public ssh runenv from our private server management?
#     later option: ansible execution (provide some ansible files + configure them separately)
#     also the thing about background tasks and non-background tasks?
#     A solid solution could be the use of a directory which contains
#     files corresponding to the execution env names. Then the masysmaci
#     would search a directory in its own directory (predefined tasks)
#     but also allow searching an additional private conf directory)
#     -> ASEL. Then how is SSH config described. Possibly best "not at all", i.e.
#     by SSH ~/.ssh/config itself. For docker running, it should be simply
#     possible to supply the .ssh directory; then again: this does not allow
#     for apropriate separation :(
#     but: multiple ssh configs can be concatenated (will require absolute paths?).
#     Additionally, it is possible to transfer any config file to a longish
#     set of commandline args. ssh config can do includes so stop worrying :)
#     Angabe von run-env: <property key="masysma.ci.runenv" value="ssh:i386"/>
#     <gar nichts>, ssh:name, ansible:name. We are still missing a way to
#     indicate direct vs. background processes? Could define a separate
#     property for the purpose?
# [ ] manaual triggering
#     should still honor configured execution type. thus not only scan by
#     trigger but also by non-default run env

################################################################################
## TRIGGER CODE ################################################################
################################################################################

# TODO z once it works, one can externalize this in a modular fashion

# -- default/debug emtpy trigger -----------------------------------------------

sub trigger_empty_add {
	print "[DEBUG] TRIGGER + N_IMPL reponame=$_[0], target=$_[1], val=$_[2]\n";
}

sub trigger_empty_remove {
	print "[DEBUG] TRIGGER - N_IMPL reponame=$_[0]\n";
}

sub trigger_empty_determine_changed {
	# pass
	return ();
}

# -- trigger_newver ------------------------------------------------------------

my %trigger_newver;

# $1 reponame, $2 trigger-target [$2 trigger not used]
sub trigger_newver_add {
	# skip add if already present because we will not detect the change
	# if we update it here...
	return if(defined($trigger_newver{$_[0]}) and
				$trigger_newver{$_[0]}->{target} eq $_[1]);
	# for now assume there is just one target to be triggered on version
	# changes (otherwise there would not be a defined order and chaos
	# emerges?)
	$trigger_newver{$_[0]} = {target => $_[1],
				version => trigger_newver_get_version($_[0])};
}

# $1 reponame
sub trigger_newver_remove {
	delete $trigger_newver{$_[0]};
}

# return targets to trigger in (repo,target) list of kv
sub trigger_newver_determine_changed {
	my @retlist = ();
	for my $repo (keys %trigger_newver) {
		my $newver = trigger_newver_get_version($repo);
		if($newver ne 0 and $newver ne
					$trigger_newver{$repo}->{version}) {
			push @retlist, {
				repo   => $repo,
				target => $trigger_newver{$repo}->{target}
			};
			$trigger_newver{$repo}->{version} = $newver;
		}
	}
	return @retlist;
}

# extract version information from repository given by parameter.
# this is necessary to be able to check for version changes between multiple
# invocations. The other subroutines above, however, are not a sufficient
# API yet.
# $1 reponame, return current version or 0 if dirty (-> no new version)
sub trigger_newver_get_version {
	my $git = Git::Wrapper->new("$root/$_[0]");
	return 0 if(scalar(grep { $_ eq "* master" } $git->branch) != 1 or
							$git->status->is_dirty);

	my $chckf = "$root/$_[0]/debian-changelog.txt";
	if(-f $chckf) {
		open my $file, '<:encoding(UTF-8)', $chckf;
		my $verl = <$file>; 
		close $file;
		$verl =~ s/[a-z0-9]+ ([^)]+) stable; .*$/$1/g;
		return $verl;
	} else {
		# TODO z might want to devise something smarter
		my @logs = $git->log();
		return $logs[0]->id;
	}
}

#-- trigger_topleveladded ------------------------------------------------------

my %trigger_topleveladded_files;
my %trigger_topleveladded_triggers;

sub trigger_topleveladded_add {
	$trigger_topleveladded_triggers{$_[0]} = {target => $_[1],
							pattern => $_[2]};
}

sub trigger_topleveladded_remove {
	delete $trigger_topleveladded_triggers{$_[0]};
}

sub trigger_topleveladded_determine_changed {
	my %thisround;
	opendir(my $dir, $root);
	while(my $entry = readdir($dir)) {
		next unless (-f "$root/$entry");
		$thisround{$entry} = 1;
	}
	for my $file (keys %trigger_topleveladded_files) {
		# has been deleted
		if(!defined($thisround{$file})) {
			delete $trigger_topleveladded_files{$file};
		}
	}
	my %rvtrigger;
	for my $file (keys %thisround) {
		# has been added
		if(!defined($trigger_topleveladded_files{$file})) {
			$trigger_topleveladded_files{$file} = 1;
			while(my ($repo, $conf) =
					each %trigger_topleveladded_triggers) {
				my $plen = length($conf->{pattern});
				if(($plen le length($file)) and
						($conf->{pattern} eq
						substr($file, -$plen))) {
					$rvtrigger{$repo.".".$conf->{target}
									} = {
						repo   => $repo,
						target => $conf->{target}
					};
				}
			}
		}
	}
	return values %rvtrigger;
}

my %triggers = (
	newver => {
		add               => \&trigger_newver_add,
		remove            => \&trigger_newver_remove,
		determine_changed => \&trigger_newver_determine_changed,
	},
	topleveladded => {
		add               => \&trigger_topleveladded_add,
		remove            => \&trigger_topleveladded_remove,
		determine_changed => \&trigger_topleveladded_determine_changed,
	},
	# TODO z it seems for now we do not even need cron. ASTAT: The next thing should either be the working env declaration definiton+processing (stored in known_repos table?) and or the next thing could also be the package synchronization implementation including repo creation if absent.
	cron => {
		add               => \&trigger_empty_add,
		remove            => \&trigger_empty_remove,
		determine_changed => \&trigger_empty_determine_changed,
	},
);

################################################################################
## MAIN CI CODE ################################################################
################################################################################

my $dom_parser = new XML::DOM::Parser;
my %trigger_runenvs;
my %known_repos;

sub process_properties {
	my ($entry, $doc) = @_;
	my $proplst = $doc->getElementsByTagName("property");
	for(my $i = 0; $i < $proplst->getLength(); $i++) {
		my $curi = $proplst->item($i);
		my $name = $curi->getAttribute("name");
		next unless ($name eq "masysma.ci.trigger" or $name eq "masysma.ci.runenv");

		my $target = $curi->getParentNode()->getAttribute("name");
		my $value = $curi->getAttribute("value");
		if($name eq "masysma.ci.trigger") {
			my @trigger = split("=", $value, 2);
			my $trigger_val = $#{trigger} eq 1? $trigger[1]: "";
			if(defined($triggers{$trigger[0]})) {
				$triggers{$trigger[0]}->{add}->($entry, $target,
								$trigger_val);
			} else {
				print "[ERROR] Trigger type \"$trigger[0]\"".
							" not available.\n";
			}
		} elsif($name eq "masysma.ci.runenv") {
			my @type = split(":", $value, 2);
			my $runenv_val;
			if($type[0] eq "ssh") {
				$runenv_val = { type => "ssh",
							conn => $type[1] };
			} else {
				print "[ERROR] Runenv $type[0] not ".
							"implemented.\n";
			}
			if(!defined($trigger_runenvs{$entry})) {
				$trigger_runenvs{$entry} = {$target
								=> $runenv_val};
			} else {
				$trigger_runenvs{$target}{$target} =
								$runenv_val;
			}
		} else {
			print("[ERROR] Program bug.\n");
		}
	}
}

while(1) {
	printf "[INFO ] checking for changes...\n";

	# For now, all XML files are parsed each round and the add functions
	# of the triggers are called every time again. This is to allow changes
	# to the files to be detected and processed. On the downside, it
	# processes also uncommited intermediate versions and reads a lot of
	# files just for rarely finding changes?
	my %this_round;
	opendir(my $dir, $root);
	while(my $entry = readdir($dir)) {
		next unless (-d "$root/$entry/.git" and
						-f "$root/$entry/build.xml");
		$this_round{$entry} = 1;
		#next if $known_repos{$entry};
		
		my $doc = $dom_parser->parsefile("$root/$entry/build.xml");
		process_properties($entry, $doc);

		# Idea for one-level import. It turned out it won't be
		# needed for now.
		#my $imports = $doc->getElementsByTagName("import");
		#for(my $i = 0; $i < $imports->getLength(); $i++) {
		#	my $file = $imports->item($i)->getAttribute("file");
		#	process_properties($entry,
		#		$dom_parser->parsefile($file)) if(-f $file);
		#}

		#$known_repos{$entry} = 1;
	}
	closedir($dir);
	# handle repo deletions
	for my $repo (grep { not $this_round{$_} } (keys %known_repos)) {
		for my $trt (keys %triggers) {
			$triggers{$trt}->{remove}->($repo);
		}
	}
	@known_repos{keys %this_round} = 1;

	my %run_this_round;
	for my $trt (keys %triggers) {
		my @changed = $triggers{$trt}->{determine_changed}->();

		for my $to_run (@changed) {
			my $runkey = $to_run->{repo}.".".$to_run->{target};
			next if(defined($run_this_round{$runkey}));
			$run_this_round{$runkey} = 1;

			my @ant_args = ("-buildfile", $root."/".$to_run->{repo},
							$to_run->{target});

			if(defined($trigger_runenvs{$to_run->{repo}}{
							$to_run->{target}})) {
				# Need to run with specific runenv. TODO ASTAT
				print("[ERROR] runenv execution not implemented. should run ssh -F here.");
			} else {
				print("[INFO ] Running ant ".join(" ",
							@ant_args)."\n");
				system("ant", @ant_args) or 1;
				if($? == 0) {
					print("[INFO ] ant completed ".
							"successfully.\n");
				} else {
					print("[WARNI] Failed to invoke ant: ".
								$?."\n");
				}
			}
			# $to_run->{repo}, $to_run->{target}
		}
	}
	sleep 5;
}
