---
section: 32
x-masysma-name: masysmaci/main
title: Ma_Sys.ma CI
date: 2020/03/28 17:56:53
lang: en-US
author: ["Linux-Fan, Ma_Sys.ma (Ma_Sys.ma@web.de)"]
keywords: ["masysmaci", "ci", "perl", "mdvl"]
x-masysma-version: 2.0
x-masysma-repository: https://www.github.com/m7a/co-ci
x-masysma-website: https://masysma.net/32/masysmaci_main.xhtml
x-masysma-owned: 1
x-masysma-copyright: (c) 2019, 2020, 2023, 2024 Ma_Sys.ma <info@masysma.net>
---
Overview
========

The Ma_Sys.ma Continuous Integration system (short: _Ma_Sys.ma CI_) attempts to
be a single-user, lightweight and automation-friendly system to perform a
tightly defined set of tasks related to the automatic building of self-made
Debian packages when their on-disk changelogs and repositories indicate changes
and the synchronization to a self-hosted private repository.

It was created out of necessity because existing systems were either very
large (e.g. Gitlab and Jenkins), unstable (e.g. Concourse) or too difficult
to automate properly. As a unique feature, Ma_Sys.ma CI does not require a
Git server, nor database of any kind. Instead, it takes repositories from below
a common root directory as its input and writes logfiles to directory
`x-co-ci-logs` as its only output.

To function correctly, Ma_Sys.ma CI requires at least three other Ma_Sys.ma
components:

 * [maartifact(11)](../11/maartifact.xhtml)
 * [masysmaci/build(32)](masysmaci_build.xhtml)
 * [masysmaci/pkgsync(32)](masysmaci_pkgsync.xhtml)

Building an individual package with Docker
==========================================

In case you want to build a Ma_Sys.ma program without having to first dig
thorugh the configuration for the Ma_Sys.ma CI, most of the programs can
be built as follows by making use of a precompiled Ma_Sys.ma CI container,
e.g. for package `mdvl-big4` which comes from the repository `bo-big`
(see [big4(32)](../32/big4.xhtml)).

	$ mkdir root
	$ cd root
	$ sudo -s
	# chown 1000:1000 .
	# maquickpkg() { docker run --rm -it -v "$(pwd):/home/masysmaci/wd" masysma/ci:20240428 /bin/sh -exc "cd /home/masysmaci/wd && git clone \"https://github.com/m7a/$1\" && cd \"$1\" && ant package"; }; maquickpkg bo-big
	# exit

After this, a new file `mdvl-big4_..._all.deb` should have been created in
directory `root` as a result of the build process.

Running in Docker
=================

To get started with the CI using Docker, download the repository to a directory
callled `co-ci` and start it with `docker-compose`:

	$ mkdir root
	$ cd root
	$ git clone https://www.github.com/m7a/co-ci
	$ cd co-ci
	$ docker-compose up

This builds the necessary images and afterwards starts containers equipped for
building packages.

Getting started: Building existent and new Packages
===================================================

Try out building a package by downloading its repository:

	$ cd root
	$ git clone https://www.github.com/m7a/bo-big
	$ cd bo-big

## Using Docker

When using Docker (as described in the previous section), the CI should then
trigger automatically after a few minutes.

## Running Manually

If you don't want to use docker and rather run the CI task on a local or
virtual machine, you can trigger it from the co-ci subdirectory as follows:

	$ ant runci

This runs the CI once by traversing through all detected repositories and
executes all associated actions. To run it continuously in a loop and with
proper logging, run script `cimain.sh` instead.

By default, it expects to be able to install missing build dependencies by
using `sudo -n apt-get update` and `sudo -n apt-get -y install <...>` commands.
It may be necessary to adjust this behaviour in `ant-build-template.xml` for
running on a non-container machine. In case you are creating a custom build VM
or such, you could also consider installing the `51-masysma-apt` sudo
configuration provided as part of this repository.

## Results

Afterwards, package `mdvl-d5man2` should become available through the reprepro
repository at `/var/tmp/masysmacirepo` (which is the default location). In case
of failure, consult the logs in directory `root/x-co-ci-logs`.

To build your own package, provide files `build.xml`, `debian-changelog.txt` and
`hello.c` from the [masysmaci/build(32)](masysmaci_build.xhtml) documentation
in a directory e.g. called `hello` and add the following lines to `build.xml`:

~~~{.xml}
<!-- CI INTEGRATION -->
<target name="autoci" depends="autopackage"/>
~~~

Make it a git repository as follows:

	$ cd root/hello
	$ git init .
	$ git add .
	$ git commit -m "Initial commit. / Hello world example."

As soon as the changes are commited, the CI should pick up the changes and build
the `mdvl-hello` package proposed in the
[masysmaci/build(32)](masysmaci_build.xhtml) documentation.

System Configuration
====================

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
architectures to run containers, check the following files:

This advanced configuration is made of two files: `docker-compose.yml` and
`Dockerfile`. Changing them is not “CI-specific” and works according to the
syntax and semantics known from Docker.

Key Files and Signatures
========================

The repository contains key material in directory `dot_gnupg_sample`.
It contains public and private keys used for signing Debian packages added to
the reprepro repository. As the directory name already implies, they are
considered _sample_ keys and should only be used for testing purposes. Upon
deciding to use Ma_Sys.ma CI productively, it is _highly recommended_ to switch
to independently created and _private_ keys. The script to re-generate
`dot_gnupg_sample` (with different keys) is provided in
`regenerate_dot_gnupg_sample.sh`. Note that for most cases, it is recommended
to generate the keys “manually” rather than using the script as to set a
different user name, e-mail etc.

License
=======

	Ma_Sys.ma CI 2.0, (c) 2019, 2020, 2023, 2024 Ma_Sys.ma <info@masysma.net>.
	
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
