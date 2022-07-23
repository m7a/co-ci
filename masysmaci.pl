#!/usr/bin/perl
# Ma_Sys.ma CI 1.0.1, Copyright (c) 2019, 2020, 2022 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.
#
# This file provides the actual CI implementation.

use strict;
use warnings FATAL => 'all';
use autodie;
use threads;
use threads::shared;

use Try::Tiny;
use File::Basename;
use Cwd qw(abs_path);
use XML::DOM;            # libxml-dom-perl
use Git::Wrapper;        # libgit-wrapper-perl
use Proc::Simple;        # libproc-simple-perl
require Thread::Queue;   # (perl-modules-5.24)
require Term::ANSIColor;
use Dancer2;             # libdancer2-perl

# use Data::Dumper 'Dumper'; # debug only

# -- constants -----------------------------------------------------------------
my $root   = abs_path(dirname($0)."/..");
my $cidir  = "co-ci";
my $logdir = "x-co-ci-logs";

# Dancer2 constant configuration
set content_type => "text/plain";
set charset      => "UTF-8";

################################################################################
## LOGGING #####################################################################
################################################################################

# Now it seems a little strange that one would need to write one's own but that
# is it as far as I can see...

$| = 1; # auto-flush STDOUT upon line ending
binmode STDOUT, ":utf8"; # otherwise gives weird error...

# $_[0] color
# $_[1] message
sub log_line {
	my ($sec, $min, $hour, $day, $mon, $year, $_wday, $_yday, $_isdst) =
								localtime(time);
	$year += 1900;
	print Term::ANSIColor::color($_[0]) if($^O ne "MSWin32");
	chomp $_[1];
	printf("%04d/%02d/%02d %02d:%02d:%02d %s",
				$year, $mon, $day, $hour, $min, $sec, $_[1]);
	print Term::ANSIColor::color("reset") if($^O ne "MSWin32");
	print "\n";
}

sub log_debug   { log_line("blue",        "[ DEBUG ] ".$_[0]); }
sub log_info    { log_line("white" ,      "[MESSAGE] ".$_[0]); }
sub log_warning { log_line("bold yellow", "[WARNING] ".$_[0]); }
sub log_error   { log_line("bold red",    "[ ERROR ] ".$_[0]); }

################################################################################
## TRIGGER CODE ################################################################
################################################################################

# -- default/debug emtpy trigger -----------------------------------------------

sub trigger_empty_add {
	# pass
	return 0
}

sub trigger_empty_remove {
	# pass
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
				defined($trigger_newver{$_[0]}->{$_[1]}));
	$trigger_newver{$_[0]} = {} if(!defined($trigger_newver{$_[0]}));
	$trigger_newver{$_[0]}->{$_[1]} = trigger_newver_get_version($_[0]);
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
		if($newver ne 0) {
			for my $target (keys %{$trigger_newver{$repo}}) {
				if($newver ne $trigger_newver{$repo
								}->{$target}) {
					push @retlist, {repo   => $repo,
							target => $target};
					$trigger_newver{$repo}->{$target} =
								$newver;
				}
			}
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
	closedir($dir);
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
				if(($plen <= length($file)) and
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

# check for changes
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
	# avoid errors for missing trigger types, special type `none`
	none => {
		add               => \&trigger_empty_add,
		remove            => \&trigger_empty_remove,
		determine_changed => \&trigger_empty_determine_changed,
	},
	# does not seem to be needed as of now...
	cron => {
		add               => \&trigger_empty_add,
		remove            => \&trigger_empty_remove,
		determine_changed => \&trigger_empty_determine_changed,
	},
);

################################################################################
## INITIALIZATION ##############################################################
################################################################################

my $dom_parser      = new XML::DOM::Parser; # check for changes
my %trigger_runenvs :shared;                # check for changes, REST r/o
my %known_repos     :shared;                # check for changes, REST r/o
my $queue_build     = Thread::Queue->new(); # check for changes, REST

# ssh options for each ssh runenv.            check for changes
my %ssh_runenvs = (
	_all => {}
);

# used for webserver
my %conf = (
	address => "127.0.0.1",
	port    => 9030,
);

# -- ssh options ---------------------------------------------------------------
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
		log_warning("File $_[0] does not exist. Not processed.");
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
				log_warning("$_[0]: Unknown element: ".
							$sub->getTagName());
			}
		}
	}
	my $confel = $doc->getElementsByTagName("conf");
	for(my $i = 0; $i < $confel->getLength; $i++) {
		for my $sub ($confel->item($i)->getChildNodes()) {
			next unless $sub->getNodeType() eq ELEMENT_NODE and
					$sub->getTagName() eq "property";
			$conf{$sub->getAttribute("name")} =
						$sub->getAttribute("value");
		}
	}
	my $incl = $doc->getElementsByTagName("include");
	for(my $i = 0; $i < $incl->getLength; $i++) {
		proc_masysmaci_xml(masysmaci_xml_value($incl->item($i),
								"file"));
	}
	$doc->dispose();
}
proc_masysmaci_xml("$root/$cidir/masysmaci.xml");

################################################################################
## BACKGROUND THREAD: DEQUEUE AND BUILD ########################################
################################################################################

# -- logging and subprocesses --
# logging and subprocess management. these structures are indexed by
# repository.target (because repositories are not deleted from this map even
# if they are no longer on disk, they might be re-added and in this case old
# logfiles should not be overwritten).
my %log_counters = (); # index repository.target        -> integer
my %subprocesses = (); # index repository.target.number -> Process::Simple

share(%log_counters);  # also needed r/o by log printing from server

mkdir "$root/$logdir" if(not -d "$root/$logdir");

# TODO z support spaces in root. simple "' '" did not seem to work in a first test.
while(<"$root/$logdir/*.txt">) {
	# format is repository.target.number.txt
	my @fns = split(/\./, basename($_));
	pop @fns; # remove extension
	my $number = pop @fns;
	my $key = join(".", @fns);
	$log_counters{$key} = $number if(!defined($log_counters{$key}) or
					$number > $log_counters{$key});
}

sub check_background_process_status {
	my $proccount = 0;
	my $procevent = 0;
	while(my ($logid, $process) = each (%subprocesses)) {
		if(!$process->poll()) {
			$procevent = 1;
			if($process->exit_status eq 0) {
				log_info("Background process ".$logid.
						" finished successfully.");
			} else {
				log_warning("Background process ".$logid.
						" finished with error code ".
						$process->exit_status);
			}
			delete $subprocesses{$logid};
		}
		$proccount++;
	}
	log_info("Currently running $proccount background processes.")
					if($proccount and not $procevent);
}

my $thread_build = threads->create(sub {
	while(1) {
		# {type => "TERM"}
		# {type => "CHECK_BACKGROUND_PROCESS_STATUS"}
		# {type => "RUN", runenv => $runenv, to_run => $to_run}
		my $query = $queue_build->dequeue();

		last if($query->{type} eq "TERM"); # poison-pill termination

		if($query->{type} eq "CHECK_BACKGROUND_PROCESS_STATUS") {
			check_background_process_status();
		} elsif($query->{type} eq "RUN") {
			my %runenv = %{$query->{runenv}};
			my $to_run = $query->{to_run};
			my $runkey = $to_run->{repo}.".".$to_run->{target};
			
			my $executable;
			my @params;
			if($runenv{type} eq "local") {
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
				# TODO z Might want to add support for Ansible
				# here. Note that we might send some parameters
				# to Ansible that are defined in the original
				# XML... but the current system should be
				# flexible enough to simply add this
				# functionality.
				log_warning("Should call runenv ".
						"\"$runenv{type}\" but this ".
						"type is not implemented!");
				next;
			}

			my $printexe = $executable." ".join(" ", @params);
			my $logidx = (defined($log_counters{$runkey}))?
						$log_counters{$runkey} + 1: 1;
			$log_counters{$runkey} = $logidx;
			my $logid = $runkey.".".$logidx;
			my $logf = "$root/$logdir/$logid.txt";
			my $proc = Proc::Simple->new();
			$proc->redirect_output($logf, $logf);
			$proc->start($executable, @params);
			
			if($runenv{bg}) {
				$subprocesses{$logid} = $proc;
				log_info("Running in background: $printexe...");
			} else {
				log_info("Running $printexe, logf=$logf...");
				my $haveln = 0;
				# wait for log file to appear...
				sleep 1 while(not -f $logf and $proc->poll());
				do {
					# do not attempt to print if no log
					# present...
					last if not -f $logf;
					open my $file, '<:encoding(UTF-8)',
									$logf;
					my $curln = 0;
					while(my $line = <$file>) {
						log_info("| $line")
							if($curln >= $haveln);
						$curln++;
						last if not $proc->poll();
					}
					$haveln = $curln;
					close $file;
				} while($proc->poll());
				my $rv = $proc->exit_status();
				if($rv == 0) {
					log_info("Subprocess completed ".
							"successfully.");
				} else {
					log_warning("Failed to invoke ".
							"subprocess: $rv");
				}
			}
		} else {
			log_error("Unknown query type $query->{type}.");
		}
	}
});

################################################################################
## BACKGROUND THREAD TIMER CHECK FOR CHANGES ###################################
################################################################################

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
						"masysma.ci.trigger.param"})?
						$prop_by_t{$target}->{
						"masysma.ci.trigger.param"}: ""
				);
			} else {
				log_error("Trigger type \"$type\" ".
							"is not available.");
			}
		}
		my %runenv_val :shared;
		if(defined($prop_by_t{$target}->{"masysma.ci.runenv"})) {
			%runenv_val = (
				type => $prop_by_t{$target}->{
						"masysma.ci.runenv"},
				name => $prop_by_t{$target}->{
						"masysma.ci.runenv.name"},
				bg   => defined($prop_by_t{$target}->{
						"masysma.ci.runenv.bg"})?
						$prop_by_t{$target}->{
						"masysma.ci.runenv.bg"}: 0,
			);
		} else {
			# Design: We need to store this to be able to later
			# retrieve the list of targets. Otherwise and previously
			# it was enough to only save the runenv_val for those
			# items which were not local / bg=0
			%runenv_val = (type => "local", bg => 0);
		}
		
		lock(%trigger_runenvs);
		if(!defined($trigger_runenvs{$entry})) {
			my %assoc :shared;
			$assoc{$target} = \%runenv_val;
			$trigger_runenvs{$entry} = \%assoc;
		} else {
			$trigger_runenvs{$entry}{$target} =
						\%runenv_val;
		}
	}
}

sub check_for_changes {
	log_info("Checking for changes...");

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

		my $doc = try {
			return $dom_parser->parsefile("$root/$entry/build.xml");
		} catch {
			log_warning("XML parse failure for ".
				"$root/$entry/build.xml: $_ skipping...");
			return 0;
		};
		next if($doc eq 0);

		process_properties($entry, $doc);
		$doc->dispose();

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
		delete $known_repos{$repo};
	}
	@known_repos{keys %this_round} = 1;
}

# $_[0]: to run
sub enqueue_to_run {
	my $to_run = shift;
	# This separate variable $hash is needed because of $trigger_runenv
	# being shared...
	my $hash   = $trigger_runenvs{$to_run->{repo}};
	my $runenv = $hash->{$to_run->{target}};
	$queue_build->enqueue({type => "RUN", runenv => $runenv,
							to_run => $to_run});
}

my $thread_background_timer = threads->create(sub {
	my $is_interrupted = 0;
	$SIG{INT} = sub { $is_interrupted = 1; };
	$SIG{TERM} = $SIG{INT};
	while(not $is_interrupted) {
		check_for_changes();

		$queue_build->enqueue({type =>
					"CHECK_BACKGROUND_PROCESS_STATUS"});

		my %run_this_round;
		for my $trt (keys %triggers) {
			my @changed = $triggers{$trt}->{determine_changed}->();
			for my $to_run (@changed) {
				my $runkey = $to_run->{repo}.".".
							$to_run->{target};
				next if(defined($run_this_round{$runkey}));
				$run_this_round{$runkey} = 1;

				enqueue_to_run($to_run);
			}
		}
		for(my $i = 0; $i < 5 and not $is_interrupted; $i++) {
			sleep(2);
		}
	}
});

################################################################################
## SIGNAL HANDLING #############################################################
################################################################################

$SIG{INT} = sub {
	# leading \n to fix mis-indented line with the ^C on it...
	print "\n-- Termination signal received --\n";
	$queue_build->enqueue({type => "TERM"});
	$thread_background_timer->kill("SIGTERM");
	log_info("Join background timer thread...");
	$thread_background_timer->join();
	log_info("Join build thread...");
	$thread_build->join();
	log_info("Finished.");
	exit(0);
};
$SIG{TERM} = $SIG{INT};

################################################################################
## REST INTERFACE ##############################################################
################################################################################

set host => $conf{address};
set port => $conf{port};

sub rest_is_true {
	my $val = shift;
	return (defined($val) and $val eq "1");
}

sub rest_build_repo {
	my $repository = shift;
	my $list = "";
	for my $target (keys %{$trigger_runenvs{$repository}}) {
		enqueue_to_run({repo => $repository, target => $target});
		$list .= $target."\n";
	}
	return $list;
}

sub rest_build_repo_target {
	my ($repository, $target) = @_;
	print "[repository=$repository,target=$target]\n";
	if(defined($trigger_runenvs{$repository}{$target})) {
		enqueue_to_run({repo => $repository, target => $target});
		return "$repository/$target\n";
	} else {
		send_error "Repository/Target combination does not exist. ".
							"Not found.", 404;
	}
}

get "/" => sub {
	return "/build\n/term\n";
};

get "/build" => sub {
	return join("", map { "/build/$_\n" } keys %known_repos);
};

get "/build/:repository" => sub {
	my $repository = route_parameters->get("repository");
	if(rest_is_true(request->header("x-masysma-post"))) {
		return rest_build_repo $repository;
	} else {
		my $runenv = $trigger_runenvs{$repository};
		return join("", map { "/build/$repository/$_\n" }
							keys %{$runenv});
	}
};

get "/build/:repository/:target" => sub {
	my $repository = route_parameters->get("repository");
	my $target = route_parameters->get("target");

	if(rest_is_true(request->header("x-masysma-post"))) {
		return rest_build_repo_target($repository, $target);
	} else {
		my $runkey = "$repository.$target";
		if($runkey =~ /^[a-z0-9_.-]+$/) {
			if(defined($log_counters{$runkey})) {
				my $logf = "$root/$logdir/$runkey".
						".$log_counters{$runkey}.txt";
				my $cntbuf = "";
				open my $file, '<:encoding(UTF-8)', $logf;
				while(my $line = <$file>) {
					$cntbuf .= $line;
				}
				close $file;
				return $cntbuf;
			} else {
				send_error "No build logs found.", 404;
			}
		} else {
			send_error "Misformatted input. Not found.", 404;
		}
	}
};

post "/term" => sub {
	$SIG{INT}->();
};

post "/build/:repository" => sub { # means trigger all
	return rest_build_repo route_parameters->get("repository");
};

post "/build/:repository/:target" => sub {
	# means trigger one
	my $repository = route_parameters->get("repository");
	my $target = route_parameters->get("target");
	return rest_build_repo_target($repository, $target);
};

start;
