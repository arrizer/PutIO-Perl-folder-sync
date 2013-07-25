PutIO folder sync
-----------------

This handy perl script helps you downloading whole folders from the Put.io webservice on a regular basis. Just set up folders from your Account and a local path and the script will keep stuff in snyc for you (very useful for fetching stuff thats automatically downloaded to put.io via e.g. torrent RSS feeds).

INSTALLATION
============

The script requires the following perl modules to be installed:

WebService::PutIOv2 (get it here: https://github.com/Pro/WebService-PutIOv2)
Getopt::Long
Data::Dumper
LWP::UserAgent
XML::Simple

On Windows additionally:
Win32::Console::ANSI

Use 'install_perl_modules.sh' to install/update the modules via the cpan tool

Init submodule
--------------
The Put.io WebService api is accesses through https://github.com/Pro/WebService-PutIOv2
This repository is included into this as a submodule.

Simply checkout this repository, then use the following commands to additionally check out the WebService-PutIOv2 repo:

git submodule init
git submodule update


Alternatively you can also download the content of the WebService-PutIOv2 repo directly into the corresponding folder.

SETUP
=====

Rename config.xml.template to config.xml and enter your authentication token (get it here: https://api.put.io/v2/oauth2/authenticate?client_id=411&response_type=code&redirect_uri=http://profanter.me/putio/perl).

For each folder you want to sync, add a block like this:

  <sync>
    <remote_path>TV Shows</remote_path>
    <local_path>/AnkhMorpork/Series/Inbox</local_path>
  </sync>

to the config.xml (inside <putiosyncconfig>).

See the config file template for details about the configuration.

RUN
===

To run the script, simply use

$ perl putiosync.pl

from the command line.
Use the -h flag to see all available options.
I recommend to schedule the script via cronjob, launchd or your native system task scheduler.