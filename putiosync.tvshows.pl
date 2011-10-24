#!/usr/bin/perl

use TVDB::API;
use Data::Dumper;

die "This script is not meant to be run separately!" if(!$config);

my $tvdb = TVDB::API::new('5EFCC7790F190138');

foreach my $task (@{$config->{"tvshows"}}){
  my $inbox = $task->{"inbox"};
  if(!-e $inbox){
    printfv(0, "The TV shows organizer inbox folder '%s' does not exist", $inbox);
    next();
  }
  if(!-e $task->{"path"}){
    printfv(0, "The TV shows library folder '%s' does not exist", $task->{"path"});
    next();
  }
  
  printfv(0, "Organizing TV shows in '%s'...", $inbox);
  my @files = filesInFolder($inbox);
  foreach my $file (@files){
    my $match = matchFile($inbox.$file);
    next() if(!$match);
    printfv(0, "-> %s S%02iE%02i '%s'", $match->{"SeriesName"}, $match->{"SeasonNumber"}, $match->{"EpisodeNumber"}, $match->{"EpisodeName"});
    moveFile($match, $task->{"path"}, $task->{"foldername"}, $task->{"filename"});
  }
}

sub matchFile
{
  my $file = shift;
     $file =~ m!(.*)\/([^\/]+)\.([0-9a-z]+)$!gi;
  my ($path, $filename, $extension) = ($1, $2, $3);
  
  my ($series, $season, $episode) = ("","","");
  
  my $match_filename = $filename;
  $match_filename =~ s/\./ /gi;
  my @extractors = ('(.*)\s*S\s*([0-9]+)\s*E([0-9]+)\s*(.*)$', 
                    '(.*)\s*\s*([0-9]+)\s*[xX]([0-9]+)\s*(.*)$');
  my $extracted = 0;
  foreach my $regexp (@extractors){
    $match_filename =~ m/$regexp/gi;
    $series = $1;
    $season = scalar $2;
    $episode = scalar $3;
    $series =~ s/(^\s+|\s$)//gi;
    $series =~ s/,_/ /gi;
    #$series =~ s/(the|der|die|das|les|le|la)//gi;
    if($series =~ m/\S+/ and $season =~ m/^[0-9]+$/ and $episode =~ m/^[0-9]+$/ and $season > 0 and $episode > 0){
      $extracted = 1;
      last;
    }
  }
  if($extracted){
    printfv(1, "Looking for '%s' S%02iE%02i...", $series, $season, $episode);
    my $item = undef;
    $item = $tvdb->getEpisode($series, $season, $episode);
    $series = disambiguateSeriesName($series, $filename) if(!$item);
    $item = $tvdb->getEpisode($series, $season, $episode) if($series);
    if($item){
      my $parent = $tvdb->getSeries($series);
      $item->{"file"} = $file;
      $item->{"extension"} = $extension;
      $item->{"path"} = $path;
      $item->{"filename"} = $filename;
      $item->{"SeriesName"} = $parent->{"SeriesName"};
      $item->{"Series"} = $parent;
      $item->{"SeriesNameSortable"} = makeSortable($item->{"SeriesName"});
      $item->{"SeasonNumberLong"} = sprintf("%02i", $item->{"SeasonNumber"});
      $item->{"EpisodeNumberLong"} = sprintf("%02i", $item->{"EpisodeNumber"});
      return $item;
    }else{
      printfv(0, "Could not match '%s' to any known show", $filename);
      return undef;
    }
  }else{
    printfv(0, "Could not guess show name, season and episode number from filename '%s'", $filename);
    return undef;
  }
}

sub disambiguateSeriesName
{
  my $series = shift;
  my $filename = shift;
  
  my $matches = $tvdb->getPossibleSeriesId($series);
  my $choice = 0;
  return undef if((scalar keys %{$matches}) == 0);
  $choice = 1 if((scalar keys %{$matches}) == 1);
  my @keys = keys(%{$matches});
  if($choice == 0){
    # More than one series matches, ask the user!
    printf("To which series does '%s' belong?\n", $filename);
    my $cnt = 0;
    foreach my $key (@keys){
      $cnt++;
      my $match = $matches->{$key};
      printf("(%i) %s\n", $cnt, $match->{"SeriesName"});
    }
  }
  
  while(!($choice > 0)){
    print("Pick one: ");
    $choice = <STDIN>;
  }
  return $matches->{@keys[$choice - 1]}->{"SeriesName"};
}

sub filesInFolder
{
  my $path = shift;
  my $subdir = shift or "";
  my @files = ();
  opendir DIR, $path.'/'.$subdir;
  foreach my $file (readdir DIR){
    next() if($file =~ m/^\./gi);
    my $file_abs = $path.'/'.$subdir.'/'.$file;
    if(-d $file_abs){
      push(@files, filesInFolder($path, $subdir."/".$file));
      next();
    }
    push(@files, $subdir.'/'.$file);
  }
  closedir DIR;
  return @files;
}

sub makeSortable
{
  my $title = shift;

  if($title =~ m!^(the|der|die|das|les|le|la) (.*)$!gis){
    $title = $2.', '.$1 if($1);
  }
  return $title;
}

sub expandPlaceholders
{
  my $match = shift;
  my $pattern = shift;
  my $map = {
    '%show%' => 'SeriesName',
    '%show_sortable%' => 'SeriesNameSortable',
    '%season%' => 'SeasonNumberLong',
    '%episode%' => 'EpisodeNumberLong',
    '%title%' => 'EpisodeName'
  };
  foreach my $key (keys %{$map}){
    my $value = $match->{$map->{$key}};
    $pattern =~ s!$key!$value!gi;
  }
  return $pattern;
}

sub moveFile
{
  my $match = shift;
  my $target = shift;
  my $folder_pattern = shift;
  my $file_pattern = shift;
  
  my $folder = expandPlaceholders($match, $folder_pattern);
  my $file = expandPlaceholders($match, $file_pattern);
  
  make_path($target.'/'.$folder.'/');
  rename $match->{"file"}, $target.'/'.$folder.'/'.$file.'.'.$match->{"extension"};
}

1;