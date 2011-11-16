use TVDB::API;
use Data::Dumper;

my $tvdb = TVDB::API::new('5EFCC7790F190138');

my $pattern_map = {
    '%show%' => 'SeriesName',
    '%show_sortable%' => 'SeriesNameSortable',
    '%season%' => 'SeasonNumberLong',
    '%episode%' => 'EpisodeNumberLong',
    '%title%' => 'EpisodeName'
};

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
    if(moveToLibrary($match, $task->{"path"}, $task->{"foldername"}, $task->{"filename"}, $pattern_map, $task->{"overwrite_strategy"})){
      push(@media_added, sprintf("%s S%02iE%02i '%s'", $match->{"SeriesName"}, $match->{"SeasonNumber"}, $match->{"EpisodeNumber"}, $match->{"EpisodeName"}));
    }else{
      printfv(0, "Not added to your library");
    }
  }
}

sub matchFile
{
  my $file = shift;
  my ($path, $filename, $extension);
  if($file =~ m!(.*)\/([^\/]+)\.([0-9a-z]+)$!gi){
    ($path, $filename, $extension) = ($1, $2, $3);
  }

  my ($series, $season, $episode) = ("","","");
  
  my $match_filename = $filename;
  $match_filename =~ s/\./ /gi;
  my @extractors = ('(.*)\s*S\s*([0-9]+)\s*E([0-9]+)\s*(.*)$', 
                    '(.*)\s*\s*[^0-9]+([0-9]+)\s*[xX]([0-9]+)\s*(.*)$', #Fornat: NAME 03x01
                    '(.*)\s*\s*([0-9]{1,2})\s*([0-9]{2})\s*(.*)$', ); #Format: NAME 102 => S01E02
  my $extracted = 0;
  foreach my $regexp (@extractors){
    $match_filename =~ m/$regexp/gi;
    $series = $1;
    $season = scalar $2;
    $episode = scalar $3;
    $series =~ s/(^\s+|\s$)//gi;
    $series =~ s/,_/ /gi;
    $series =~ s/20\d{2}//gi; #remove year
    #$series =~ s/(the|der|die|das|les|le|la)//gi;
	#printfv(0, "# %s S%02iE%02i", $series, $season, $episode);
    if($series =~ m/\S+/ and $season =~ m/^[0-9]+$/ and $episode =~ m/^[0-9]+$/ and $season > 0 and $episode > 0){
      $extracted = 1;
      last;
    }
  }
  if($extracted){
    printfv(1, "Looking for '%s' Season %02i Episode %02i...", $series, $season, $episode);
    my $item = undef;
    $item = $tvdb->getEpisode($series, $season, $episode, 1) if(!$options{"tv-shows-ask"});
    $series = disambiguateSeriesName($series, $filename, 1) if(!$item and !$options{"n"});
    $item = $tvdb->getEpisode($series, $season, $episode, 1) if($series);
    if($item){
      my $parent = $tvdb->getSeries($series, 1);
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
      printfvc(0, "Could not match '%s' to any known show", 'red', $filename);
      return undef;
    }
  }else{
    printfvc(0, "Could not guess show name, season and episode number from filename '%s'", 'yellow', $filename);
    return undef;
  }
}

sub disambiguateSeriesName
{
  my $series = shift;
  my $filename = shift;
  
  my $matches = $tvdb->getPossibleSeriesId($series, 1);
  my $choice = -1;
  return undef if((scalar keys %{$matches}) == 0);
  $choice = 1 if((scalar keys %{$matches}) == 1);
  my @keys = keys(%{$matches});
  if($choice == -1){
    # More than one series matches, ask the user!
    printf("To which series does '%s' belong?\n", $filename);
    printfvc(0, "(0) None of the listed", 'yellow');
    my $cnt = 0;
    foreach my $key (@keys){
      $cnt++;
      my $match = $matches->{$key};
      printf("(%i) %s\n", $cnt, $match->{"SeriesName"});
    }
  }
  
  while(!($choice >= 0)){
    print("Pick one: ");
    $choice = <STDIN>;
  }
  if($choice > 0){
    return $matches->{@keys[$choice - 1]}->{"SeriesName"};
  }else{
    return undef;
  }
}

1;