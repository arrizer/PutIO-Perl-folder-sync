#!/usr/bin/env perl
use CPAN;

my $windows = $^O =~ /Win32/i;

if(!$windows and getpwuid($<) ne 'root'){
  print "Please run the module installer as root!\n";
  exit();
}elsif($windows){
	my $retval = system('mkdir "%windir%\system32\putio_sync_test') >> 8;
	if($retval == 0){
		system('rmdir "%windir%\system32\putio_sync_test');
	}else{
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
  'TVDB::API',
  'Term::ReadKey',
  'WWW::Mechanize',
  'IO::Null',
  'JSON',
  'URI::Escape',
  'Mail::Sendmail',
  'Net::DNS',
  'Net::Twitter',
);

if($windows){
  # Append additional windose modules
	push(@requiredModules,"Win32::Console::ANSI");
	push(@requiredModules,"Win32::File");
}

for my $moduleName (@requiredModules){
  printf("Installing '%s'...\n", $moduleName);
  CPAN::Shell->install($moduleName);
}