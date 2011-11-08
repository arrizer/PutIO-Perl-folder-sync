#!/usr/bin/env perl
use CPAN;

if($^O !~ /Win32/i and getpwuid($<) ne 'root'){
  print "Please run the module installer as root!\n";
  exit();
} elsif($^O =~ /Win32/i) {
	my $retval = system('mkdir "%windir%\system32\putio_sync_test') >> 8;

	if ($retval == 0)
	{
		system('rmdir "%windir%\system32\putio_sync_test')
	}
	else
	{
		print "Please run the module installer as administrator!\n";
		exit();
	}
}

my @requiredModules = (
  'WebService::PutIo::Files',
  'Getopt::Long',
  'Data::Dumper',
  'LWP::UserAgent',
  'LWP::Protocol::https',
  'XML::Simple',
  'File::Path',
  'TVDB::API'
);

if($^O =~ /Win32/i)
{
	push(@requiredModules,"Win32::Console::ANSI");
	push(@requiredModules,"Win32::File");
}

for my $moduleName (@requiredModules){
  printf("Installing '%s'...\n", $moduleName);
  CPAN::Shell->install($moduleName);
}