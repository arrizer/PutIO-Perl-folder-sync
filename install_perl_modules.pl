#!/usr/bin/env perl
use CPAN;

if($^O !~ /Win32/i and getpwuid($<) ne 'root'){
  print "Please run the module installer as root!\n";
  exit();
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

for my $moduleName (@requiredModules){
  printf("Installing '%s'...\n", $moduleName);
  CPAN::Shell->install($moduleName);
}