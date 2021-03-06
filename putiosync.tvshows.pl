use Data::Dumper;

require $mypath.'/thetvdb.pl';

my $pattern_map = {
    '%show%' => 'SeriesName',
    '%show_sortable%' => 'SeriesNameSortable',
    '%season%' => 'SeasonNumberLong',
    '%episode%' => 'EpisodeNumberLong',
    '%title%' => 'EpisodeName'
};

my $series_mapping = undef;
my $mapping_file = $mypath.'/series_mapping.yaml';
if(-e $mapping_file){
	
	use YAML::XS qw(Load);

	my $hash = {
		'.*Agents of S[\s\.]*H[\s\.]*I[\s\.]*E[\s\.]*L[\s\.]*D' => "Marvel's Agents of S.H.I.E.L.D"
	};
	

 
	my $yaml;
	{
	  local $/; #Enable 'slurp' mode
	  open my $fh, "<", $mapping_file;
	  $yaml = <$fh>;
	  close $fh;
	}
	
	$series_mapping = Load($yaml);
}

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
  my @files = filesInFolder($inbox,"",1,0,$task->{"cleanup_regex"},$task->{"remove_empty_dir"}eq"true");
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
  my @extractors = ('(.*)\s*S\s*([0-9]+)\s*E([0-9]+)\s*(.*)$',          #Format: S03E05
                    '(.*)\s*\s*[^0-9]+([0-9]+)\s*[xX]([0-9]+)\s*(.*)$', #Fornat: NAME 03x01
                    '(.*)\s*\s*([0-9]{1,2})\s*([0-9]{2})\s*(.*)$',      #Format: NAME 102 => S01E02
                    '(.*)\s*Season\s*([0-9]+)\s*Episode\s*([0-9]+)\s*(.*)$');  #Format: Season 03 Episode 05
  my $extracted = 0;
  foreach my $regexp (@extractors){
    if($match_filename =~ m/$regexp/gi){     
      $series = $1;
      $season = scalar $2;
      $episode = scalar $3;
    }
    $series =~ s/(^\s+|\s$)//gi;
    $series =~ s/,_/ /gi;
    #$series =~ s/20\d{2}//gi; #remove year
    #$series =~ s/(the|der|die|das|les|le|la)//gi;
	#printfv(0, "# %s S%02iE%02i", $series, $season, $episode);
    if($series =~ m/\S+/ and $season =~ m/^[0-9]+$/ and $episode =~ m/^[0-9]+$/ and $season > 0 and $episode > 0){
      $extracted = 1;
      last;
    }
  }
  my $dateExtracted = 0;
  my $date_match_filename = $filename;
  
  
  
  my ($year, $month, $day) = (0,0,0);
  if($extracted){
  
    #Cheching for date
    my $dateExtractor = '(.*)\.([0-9]{4})\.([0-9]{2})\.([0-9]{2})\.(.*)$';
    if ($date_match_filename =~ m/$dateExtractor/gi) {
      $series = $1;
      
      $year = scalar $2;
      $month = scalar $3;
      $day = scalar $4;
      
      $series =~ s/\./ /gi;
      $dateExtracted = 1;
    }  
	
	if (defined($series_mapping)) {
		foreach my $key (keys $series_mapping) {
			if($series =~ m/$key/gi) {
				printfv(1, "Mapped '%s' to '%s'", $series, $series_mapping->{$key});
				$series = $series_mapping->{$key};
				last;			
			}
		}
	}
	
    printfv(1, "Looking for '%s' Season %02i Episode %02i...", $series, $season, $episode) unless $dateExtracted;
    printfv(1, "Looking for '%s' from %04i-%02i-%02i...", $series, $year, $month, $day) if $dateExtracted;
    my $item = undef;
    if ($dateExtracted) {
      $item = tvdbEpisodeForDate($series, $year, $month, $day) if(!$options{"tv-shows-ask"});
      my $seriesId = disambiguateSeriesName($series, $filename) if(!$item and !$options{"n"});
      printfv(1, 'Series ID for %s: %s', $series, $seriesId);
      $item = tvdbEpisodeForDateId($seriesId, $year, $month, $day) if($seriesId);
    } else {
		#Trying with year and without year, if name has year init
		my @names = ();
		push(@names,$series);
		$series =~ s/20\d{2}//gi; #remove year
		if (!grep( /^\Q$series$/, @names )){
			push(@names,$series);
		}
		foreach my $name (@names){
			printfvc(1, "Trying: $name","blue");
			  $item = tvdbEpisode($name, $season, $episode) if(!$options{"tv-shows-ask"});
			  my $seriesId = disambiguateSeriesName($name, $filename) if(!$item and !$options{"n"});
			  $item = tvdbEpisodeId($seriesId, $season, $episode) if($seriesId);
			  if ($item) {
				last;
			  }
		}
    }
    if($item){
      my $parent = tvdbSeriesId($item->{"seriesid"});
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
  
  my $matches = tvdbSearch($series);
  my @matches = @$matches;
  my $choice = -1;
  return undef if((scalar @matches) == 0);
  $choice = 1 if((scalar @matches) == 1);
  if($choice == -1){
    # More than one series matches, ask the user!
    printf("To which series does '%s' belong?\n", $filename);
    printfvc(0, "(0) None of the listed", 'yellow');
    my $cnt = 0;
    foreach my $match (@matches){
      $cnt++;
      printf("(%i) %s\n", $cnt, $match->{"SeriesName"});
    }
  }
  
  while(!($choice >= 0)){
    print("Pick one: ");
    $choice = <STDIN>;
  }
  if($choice > 0){
    return @matches[$choice - 1]->{"seriesid"};
  }else{
    return undef;
  }
}

1;