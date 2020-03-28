---
section: 32
x-masysma-name: masysmaci/main
title: Ma_Sys.ma CI
date: 2020/03/28 17:56:53
lang: en-US
author: ["Linux-Fan, Ma_Sys.ma (Ma_Sys.ma@web.de)"]
keywords: ["masysmaci", "ci", "perl", "mdpc2"]
x-masysma-version: 1.0
x-masysma-repository: https://www.github.com/m7a/co-ci
x-masysma-website: https://masysma.lima-city.de/32/masysmaci_main.xhtml
x-masysma-owned: 1
x-masysma-copyright: |
  Copyright (c) 2019, 2020 Ma_Sys.ma.
  For further info send an e-mail to Ma_Sys.ma@web.de.
---
Overview
========

The Ma_Sys.ma Continuous Integration system (short: _Ma_Sys.ma CI_) attempts to
be a single-user, lightweight and automation-friendly system to perform a
tightly defined set of tasks related to the detection of changes and invocation
of build processes.

It was created out of necessity because existing systems were either very
large (e.g. Gitlab and Jenkins), unstable (e.g. Concourse) or too difficult
to automate properly. As an unique feature, Ma_Sys.ma CI does not require a
Git server, nor database of any kind. Instead, it takes repositories from below
a common root directory as its input and writes logfiles to directory
`x-co-ci-logs` as its only output.

For Ma_Sys.ma purposes, Ma_Sys.ma CI serves specifically to detect changes to
packages, build updated package files and synchronize them to a (private) Debian
repository. The synchronization is handled by component
[masysmaci/pkgsync(32)](masysmaci_pkgsync.xhtml).

Getting started: Running in Docker
==================================

To get started with the CI quickly, download the repository to a directory
callled `co-ci` and start it with `docker-compose`:

	$ mkdir root
	$ cd root
	$ git clone https://www.github.com/m7a/co-ci
	$ cd co-ci
	$ docker-compose up

This will first build the necessary images and afterwards start three containers
equipped for building packages. Check if the CI is alive by querying its REST
endpoints:

	$ curl http://127.0.0.1:9030
	/build
	/term

Getting started: Building existent and new Packages
===================================================

Try out building a package by downloading its repository and triggering its
build:

	$ cd root
	$ git clone https://www.github.com/m7a/bo-d5man2
	$ cd bo-d5man2
	$ ant trigger

Afterwards, package `mdvl-d5man2` should become available through the reprepro
repository at `/var/tmp/masysmacirepo` (which is the default location). In case
of failure, consult the logs in directory `root/x-co-ci-logs`.

To build your own package, provide files `build.xml`, `debian-changelog.txt` and
`hello.c` from the [masysmaci/build(32)](masysmaci_build.xhtml) documentation
in a directory e.g. called `hello` and add the following lines to `build.xml`:

~~~{.xml}
<!-- CI INTEGRATION -->
<target name="package_triggered_amd64" depends="package">
	<property name="masysma.ci.trigger" value="newver"/>
</target>
~~~

Make it a git repository as follows:

	$ cd root/hello
	$ git init .
	$ git add .
	$ git commit -m "Initial commit. / Hello world example."

As soon as the changes are commited, the CI should pick up the changes and build
the `mdvl-hello` package proposed in the
[masysmaci/build(32)](masysmaci_build.xhtml) documentation. As only the target
for `amd64` was added, it will only build the package for that specific
architecture. See _Task Definition_ for how to integrate build processes for
other architectures.

System Configuration
====================

The Ma_Sys.ma CI can be configured to adept to your local environment by
multiple different means depending on what part exactly is to be configured.

## Change how the System runs through Environment Variables

The easiest way to change configuration is by using environment variables.
Any of these variables may be supplied on the commandline for `docker-compose`
or a dedicated `.env` file. See [the docker-compose
documentation](https://docs.docker.com/compose/environment-variables/) for
details.

The following environment variables are available for configuration
(default values given after `=`):

`MA_DEBIAN_MIRROR=http://ftp.de.debian.org/debian`
:   Configures the URL of a Debian mirror to use.
`MA_REPOSITORY_ROOT=/var/tmp/masysmacirepo`
:   Configures the file system location of the reprepro repository to write
    files to.
`MA_GNUPG_ROOT=./dot_gnupg_sample/`
:   Configures a `.gnupg` directory to use for the CI's container.
    The data from that directory is used to sign packages added to the
    reprepro repository. It is highly recommended to either change the
    contents of `dot_gnupg_sample` or configure a different directory here.
    See section _Key Files and Signatures_ for details.

## Change how the System is composed

The environment variables do not change how the system is composed. If you want
to change e.g. the number of containers to use for CI builds or select different
architectures to run containers for or even want to integrate with external
non-Docker _running environments_, then it becomes necessary to dig into the
details of the configuration.

This advanced configuration is made of two sides:

 1. The _Docker-side_: The selection of containers and how their images are
    built is specified in `docker-compose.yml` and `dockerfile_masysmaci`.
    Changing them is not “CI-specific” and works according to the syntax
    and semantics known from Docker.
 2. The _Ma_Sys.ma CI-side_: To configure the CI, file `masysmaci.xml` is
    processed upon starting the `masysmaci.pl` script. After changing the file
    it is thus necessary to restart the main CI container (`amd64`) for the
    changes to take effect.

As Docker changes are known from Docker, the following only documents the
specifics of file `masysmaci.xml`. _TODO ASTAT_

Here is a copy of the default configuration `masysmaci.xml`:

~~~{.xml}
<masysmaci>
	<conf>
		<property name="address" value="0.0.0.0"/>
		<property name="port"    value="9030"/>
	</conf>
	<runenv_ssh>
		<property name="StrictHostKeyChecking" value="accept-new"/>
		<property name="BatchMode" value="yes"/>
		<host name="i386" phoenixroot="/home/masysmaci/root">
			<property name="HostName" value="i386"/>
			<property name="Port" value="2222"/>
			<property name="IdentityFile" value="$MDVL_CI_PHOENIX_ROOT/co-ci/dot_ssh_server/id_ed25519_i386"/>
			<property name="User" value="masysmaci"/>
		</host>
		<host name="armhf" phoenixroot="/home/masysmaci/root">
			<property name="HostName" value="armhf"/>
			<property name="Port" value="2222"/>
			<property name="IdentityFile" value="$MDVL_CI_PHOENIX_ROOT/co-ci/dot_ssh_server/id_ed25519_armhf"/>
			<property name="User" value="masysmaci"/>
		</host>
	</runenv_ssh>
</masysmaci>
~~~

Below the top-level `masysmaci` element, there are two main elements for
configuration: `conf` and `runenv_ssh`.

Element `conf` allows for general key-value associations to be stored. Here, you
can configure the following properties:

 * `address` -- the IP address to listen on for the REST API
 * `port` -- the port to listen on for the REST API

Element `runenv_ssh` contains SSH configuration for different running
environments. The concept of a _running environment_ is similar to a
_worker_ of other CI systems -- it is the connection to a computer to run
commands on. As Ma_Sys.ma CI does this through SSH or local commands only, all
running enviroments are configured in terms of SSH connections.

The `property` elements directly below `runenv_ssh` are SSH configuration
options to set for all runenvs. In the default configuration shown above,
`BatchMode` and `StrictHostKeyChecking` are configured for non-interactive
SSH use and trust on first connection.

The individual running environments are configured by `host` elements. For any
host, there is a `name` attribute which uniquely identifies the running
environment in the Ma_Sys.ma CI. Attribute `phoenixroot`configures the
directory where all repositories can be found in. This directory needs to
be available in all running environments although in theory, not all running
environments need to access all of the repositories (it is e.g. sufficient that
they can access the repositories they are trying to build packages from).

Below the `host` element, properties are set to configure the IP address or
host name and port of the running environment to connect to (`HostName` and
`Port`). Additionally, the user to login with (`User`) and the location of the
SSH private key file to use for connection needs to be given (`IdentityFile`).
If necessary, additional SSH options can be configured with additional
`property` elements.

In the example, `$MDVL_CI_PHOENIX_ROOT` is used. Note that this is the _only_
variable that can be substituted in the properties and it always refers to the
CI host's `$MDVL_CI_PHOENIX_ROOT` and not to the running environments'!

Task Definition
===============

Tasks are defined in a `build.xml` which needs to be present in a repository's
root directory for it to be recognized by the Ma_Sys.ma CI.

Here are the definitions from `lp-cone/build.xml` as an example:

~~~{.xml}
<target name="package_triggered" depends="package">
	<property name="masysma.ci.trigger" value="newver"/>
</target>
<target name="package_triggered_i386" depends="package">
	<property name="masysma.ci.trigger"     value="newver"/>
	<property name="masysma.ci.runenv"      value="ssh"/>
	<property name="masysma.ci.runenv.name" value="i386"/>
</target>
<target name="package_triggered_armhf" depends="package">
	<property name="masysma.ci.trigger"     value="newver"/>
	<property name="masysma.ci.runenv"      value="ssh"/>
	<property name="masysma.ci.runenv.name" value="armhf"/>
</target>
~~~

A `<target>` element is recognized by the CI if it contains a property with
name `masysma.ci.trigger`. The CI-specific properties are as follows:

`masysma.ci.trigger` (required)
:   Defines the type of trigger to use.
    Currently, `newver` and `topleveladded` are available.
`masysma.ci.runenv` (default: `local`)
:   Type of running environment to use.
    Possible values: `local` or `ssh`.
`masysma.runenv.name` (optional)
:   The name of the running environment to use.
`masysma.runenv.bg` (default: `0`)
:   Specifies whether the target should run as a background process
    (allows other targets to run in parallel) or in the foreground
    (allows only that target to run).
`masysma.ci.trigger.param` (optional)
:   Specifies a parameter to pass to the trigger type.
    With `newver` this is ignored, with `topleveladded`, this specifies a
    suffix for a file to be recognized by the `topleveladded` trigger.

Whenever a trigger for any of the targets is executed, the respective targets
will be invoked by the CI. In the example, three triggers for the same
condition (`newver`) are defined to run on different running environments as
to build the `mdvl-cone` package for the three processor architectures: amd64,
i386, armhf. Note that the `masysma.ci.runenv.name` need not describe an
architecture name -- this is only the default configuration from
`masysmaci.xml`.

The `newver` trigger type
:   The `newver` trigger runs whenever a given repository is clean in the sense
    that there are no files which are not commited _and_ the package defined by
    the repository's `build.xml` appears to have a new version according to
    `debian-changelog.txt`.

The `topleveladded` trigger type
:   The `topleveladded` trigger runs whenever a file is added in the
    `$MDVL_CI_PHOENIX_ROOT` directory and its suffix matches the value from
    `masysma.ci.trigger.param`. This mechanism is used by
    [masysmaci/pkgsync(32)](masysmaci_pkgsync.xhtml) to add newly generated
    `.deb` files to the repository.

REST API
========

Some of the Ma_Sys.ma CI's features are available through a REST API listening
on port 9030 by default. The endpoints are as follows:

`/term` (POST)
:   Upon sending the POST request to this endpoint, the Ma_Sys.ma CI shuts
    down (after awaiting the termination of running foreground subprocesses).
`/build` (GET)
:   Replies with a list of all repositories recognized by the CI.
    This includes all repositories which contain a valid `build.xml`
    independently of whether they use any triggers.
`/build/:repository` (GET, POST)
:   To use this endpoint, replace `:repository` by the directory name of the
    repository. Upon querying this endpoint with GET, all targets which could be
    triggered are returned. Upon sending a POST request, all of these targets
    _are_ triggered.
`/build/:repository/:target` (GET, POST)
:   To use this endpoint, replace `:repository` by the directory name of
    the repository and `:target` by the target name to consider.
    Upon querying this endpoint with GET, the most recent build log is returned
    (or 404 if none exists yet). Upon sending a POST request, the sepcific
    target is triggered.

Key Files and Signatures
========================

The repository contains the following structure of key material:

	co-ci/
	 |
	 +-- dot_gnupg_sample/
	 |    |
	 |    +-- ...
	 |
	 +-- dot_ssh_armfh/
	 |    |
	 |    +-- authorized_keys
	 |
	 +-- dot_ssh_i386/
	 |    |
	 |    +-- authorized_keys
	 |
	 +-- dot_ssh_server/
	      |
	      +-- id_ed25519_armhf
	      |
	      +-- id_ed25519_i386

Directories `dot_ssh_armhf` and `dot_ssh_i386` contain the SSH public keys
for the SSH private keys (identities) below `dot_ssh_server`. These keys are
used for the containers to communicate with each other. The containers do not
expose their respective SSH ports and hence, their SSH services are only
available in the Docker network created by `docker-compose` and thus, hidden
from the outside world. As a result, there is no need to keep these keys
secret. In case of doubt, they may be re-generated by script `regenerate_id.sh`.

Directory `dot_gnupg_sample` contains public and private keys used for signing
Debian packages added to the reprepro repository. As the directory name already
implies, they are considered _sample_ keys and should only be used for testing
purposes. Upon deciding to use Ma_Sys.ma CI productively, it is
_highly recommended_ to switch to independently created and _private_ keys.
The script to re-generate `dot_gnupg_sample` (with different keys) is provided
in `regenerate_dot_gnupg_sample.sh`. Note that for most cases, it is recommended
to generate the keys “manually” rather than using the script as to set a
different user name, e-mail etc.

License
=======

	Ma_Sys.ma CI 1.0, Copyright (c) 2019, 2020 Ma_Sys.ma.
	For further info send an e-mail to Ma_Sys.ma@web.de.
	
	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.
	
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
