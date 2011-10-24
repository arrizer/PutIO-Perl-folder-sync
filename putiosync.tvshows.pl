#!/usr/bin/perl

use TVDB::API;
use Data::Dumper;

die "This script is not meant to be run separately!" if(!$config);

my $tvdb = TVDB::API::new('5EFCC7790F190138');

my $series_id = $tvdb->getPossibleSeriesId("Simpsons, The", [$nocache]);