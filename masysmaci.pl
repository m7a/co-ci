#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use autodie;

use File::Basename;
use Cwd qw(abs_path);
use XML::DOM; # libxml-dom-perl
use Git::Wrapper; # libgit-wrapper-perl (?)
use Proc::Simple; # libproc-simple-perl

use Data::Dumper 'Dumper'; # debug only

my $root  = abs_path(dirname($0)."/..");
my $cidir = "masysma-ci"; # TODO z switch to new naming
my $logdir = "cilogs";

# Next features
# [x] Benennung vereinheitlichen für Konfiguration
# [ ] repo management (create, add, update, remove) is separate
# [ ] run environments [CSTAT test the existing functionality / add i386 ssh container]
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
	# TODO z it seems for now we do not even need cron.
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
my %trigger_runenvs = ();
my %known_repos = ();

# ssh options for each ssh runenv.
my %ssh_runenvs = (
	_all => {}
);

# -- logging and subprocesses --

# logging and subprocess management. these structures are indexed by
# repository.target (because repositories are not deleted from this map even
# if they are no longer on disk, they might be re-added and in this case old
# logfiles should not be overwritten).
my %log_counters = (); # index repository.target        -> integer
my %subprocesses = (); # index repository.target.number -> Process::Simple
mkdir "$root/$logdir" if(not -d "$root/$logdir");
while(<"$root/$logdir/*.txt">) {
	# format is repository.target.number.txt
	my @fns = split(/\./);
	my $key = $fns[0].".".$fns[1];
	$log_counters{$key} = $fns[2] if(!defined($log_counters{$key}) or
						$fns[2] gt $log_counters{$key});
}

# -- ssh options --
# param 1: property element
# param 2: optional attribute to read
sub masysmaci_xml_value {
	my $attr = $#_ > 0? $_[1]: "value";
	my $strval = $_[0]->getAttribute($attr);
	# better solutions (which do not fail on ';' in root path) are welcome!
	$strval =~ s;\$MDVL_CI_PHOENIX_ROOT;$root;g;
	return $strval;
}
sub proc_masysmaci_xml {
	if(not -f $_[0]) {
		print("[WARNI] File $_[0] does not exist. Not processed.\n");
		return;
	}
	my $doc = $dom_parser->parsefile($_[0]);
	my $rssh = $doc->getElementsByTagName("runenv_ssh");
	for(my $i = 0; $i < $rssh->getLength; $i++) {
		next unless $rssh->item($i)->getNodeType() eq ELEMENT_NODE;
		for my $sub ($rssh->item($i)->getChildNodes()) {
			next unless $sub->getNodeType() eq ELEMENT_NODE;
			if($sub->getTagName() eq "property") {
				# top-level property
				$ssh_runenvs{_all}->{$sub->getAttribute("name")}
						= masysmaci_xml_value($sub);
			} elsif($sub->getTagName() eq "host") {
				# host-specific
				my $curr = $sub->getAttribute("name");
				$ssh_runenvs{$curr} = { _phoenixroot =>
					$sub->getAttribute("phoenixroot") };
				my $subl = $sub->getElementsByTagName(
								"property");
				for(my $j = 0; $j < $subl->getLength(); $j++) {
					my $el = $subl->item($j);
					$ssh_runenvs{$curr}->{
						$el->getAttribute("name")} =
						masysmaci_xml_value($el);
				}
			} else {
				# other
				print("[WARNI] $_[0]: Unknown element: ".
						$sub->getTagName()."\n");
			}
		}
	}
	my $incl = $doc->getElementsByTagName("include");
	for(my $i = 0; $i < $incl->getLength; $i++) {
		proc_masysmaci_xml(masysmaci_xml_value($incl->item($i),
								"file"));
	}
}

proc_masysmaci_xml("$root/$cidir/masysmaci.xml");

# -- mainloop --

sub process_properties {
	my ($entry, $doc) = @_;
	my $proplst = $doc->getElementsByTagName("property");
	my %prop_by_t; # property by target
	# read all properties group by target
	for(my $i = 0; $i < $proplst->getLength(); $i++) {
		my $curi = $proplst->item($i);
		my $name = $curi->getAttribute("name");
		next if not $name =~ /^masysma\.ci\.(trigger|runenv)/;
		my $target = $curi->getParentNode()->getAttribute("name");
		$prop_by_t{$target} = {} if(!defined($prop_by_t{$target}));
		$prop_by_t{$target}->{$name} = $curi->getAttribute("value");
	}
	# process by target
	for my $target (keys %prop_by_t) {
		if(defined($prop_by_t{$target}->{"masysma.ci.trigger"})) {
			my $type = $prop_by_t{$target}->{"masysma.ci.trigger"};
			if(defined($triggers{$type})) {
				$triggers{$type}->{add}->(
					$entry, $target,
					defined($prop_by_t{$target}->{
						"maysma.ci.trigger.param"})?
						$prop_by_t{$target}->{
						"masysma.ci.trigger.param"}: ""
				);
			} else {
				print "[ERROR] Trigger type \"$type\"".
							" not available.\n";
			}
		}
		if(defined($prop_by_t{$target}->{"masysma.ci.runenv"})) {
			my $runenv_val = {
				type => $prop_by_t{$target}->{
						"masysma.ci.runenv"},
				name => $prop_by_t{$target}->{
						"masysma.ci.runenv.name"},
				bg   => defined($prop_by_t{$target}->{
						"masysma.ci.runenv.bg"})?
						$prop_by_t{$target}->{
						"masysma.ci.runenv.bg"}: 0,
			};
			if(!defined($trigger_runenvs{$entry})) {
				$trigger_runenvs{$entry} = {$target
								=> $runenv_val};
			} else {
				$trigger_runenvs{$entry}{$target} =
								$runenv_val;
			}
		}
	}
}

while(1) {
	printf "[INFO ] checking for changes...\n";

	# -- Update repository information --
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

		# Idea for one-level import processing.
		# It turned out it is not needed for now.
		#my $imports = $doc->getElementsByTagName("import");
		#for(my $i = 0; $i < $imports->getLength(); $i++) {
		#	my $file = $imports->item($i)->getAttribute("file");
		#	process_properties($entry,
		#		$dom_parser->parsefile($file)) if(-f $file);
		#}
	}
	closedir($dir);
	# handle repo deletions
	for my $repo (grep { not $this_round{$_} } (keys %known_repos)) {
		for my $trt (keys %triggers) {
			$triggers{$trt}->{remove}->($repo);
		}
	}
	@known_repos{keys %this_round} = 1;

	# -- Check background process status --
	my $proccount = 0;
	my $procevent = 0;
	while(my ($logid, $process) = each (%subprocesses)) {
		if(!$process->poll()) {
			$procevent = 1;
			if($process->exit_status eq 0) {
				print("[INFO ] Background process ".$logid.
						" finished successfully.\n");
			} else {
				print("[WARNI] Background process ".$logid.
						" finished with error code ".
						$process->exit_status."\n");
			}
			delete $subprocesses{$logid};
		}
		$proccount++;
	}
	print("[INFO ] Currently running $proccount background processes.\n")
					if($proccount and not $procevent);

	# -- Run Commands as per change listeners --
	my %run_this_round;
	for my $trt (keys %triggers) {
		my @changed = $triggers{$trt}->{determine_changed}->();

		for my $to_run (@changed) {
			my $runkey = $to_run->{repo}.".".$to_run->{target};
			next if(defined($run_this_round{$runkey}));
			$run_this_round{$runkey} = 1;

			my %runenv = defined($trigger_runenvs{$to_run->{repo}}{
							$to_run->{target}})?
				%{$trigger_runenvs{$to_run->{repo}}{
							$to_run->{target}}}:
 				( type => "manual", background => 0, );

			my $executable;
			my @params;
			if($runenv{type} eq "manual") {
				$executable = "ant";
				@params = (
					"-buildfile",
					$root."/".$to_run->{repo}."/build.xml",
					$to_run->{target}
				);
			} elsif($runenv{type} eq "ssh") {
				$executable = "ssh";
				my %ssh_opts;
				@ssh_opts{keys %{$ssh_runenvs{_all}}} =
						values %{$ssh_runenvs{_all}};
				my %rekv = %{$ssh_runenvs{$runenv{name}}};
				my $remote_root = $rekv{_phoenixroot};
				my $connstr = $rekv{User}."@".$rekv{HostName};
				delete $rekv{User};
				delete $rekv{HostName};
				delete $rekv{_phoenixroot};
				@ssh_opts{keys %rekv} = values %rekv;
				@params = map { ("-o", "$_=$ssh_opts{$_}") }
								keys %ssh_opts;
				push(@params, $connstr);
				push(@params, "ant");
				push(@params, "-buildfile");
				push(@params, $remote_root."/".$to_run->{repo}.
								"/build.xml");
				push(@params, $to_run->{target});
			} else {
				print("[WARNI] Should call runenv \"$runenv{type}\" but this type is not implemented!\n"); # TODO z Support Ansible here. Note that we might send some parameters to ansible that are defined in the original XML... but the current system should be flexible enough to simply add this functionality.
				next;
			}

			my $printexe = "$executable ".join(" ", @params);
			if($runenv{background}) {
				my $logidx = (defined($log_counters{$runkey}))?
						$log_counters{$runkey} + 1: 1;
				$log_counters{$runkey} = $logidx;
				my $logid = $runkey.".".$logidx;
				my $logf = "$root/$logdir/$logid.txt";
				my $proc = Proc::Simple->new();
				$proc->redirect_output($logf);
				$proc->start($executable, @params);
				$subprocesses{$logid} = $proc;
				print("[INFO ] Running in background: ".
							$printexe."...\n");
			} else {
				# run directly
				print("[INFO ] Running $printexe...\n");
				system($executable, @params) or 1;
				if($? == 0) {
					print("[INFO ] subprocess completed ".
							"successfully.\n");
				} else {
					print("[WARNI] Failed to invoke ".
							"subprocess: ".$?."\n");
				}
			}
		}
	}
	sleep 5;
}
