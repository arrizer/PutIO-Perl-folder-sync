#use IMDB::Film;
use JSON;
use URI::Escape;
use WWW::Mechanize;

# yeah IMDB, we are a Firefox browser!
my $web = WWW::Mechanize->new(agent => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0a2) Gecko/20110613 Firefox/6.0a2', autocheck => 0);
my $json = $json = JSON->new->allow_nonref;

my $pattern_map = {
    '%title%' => 'Title',
    '%title_sortable%' => 'TitleSortable',
    '%year%' => 'Year',
    '%director%' => 'Director',
    '%genre%' => 'Genre',
    '%actors%' => 'Actors'
};

foreach my $task (@{$config->{"movies"}}){
  my $inbox = $task->{"inbox"};
  if(!-e $inbox){
    printfvc(0, "The movies organizer inbox folder '%s' does not exist", 'red', $inbox);
    next();
  }
  if(!-e $task->{"path"}){
    printfvc(0, "The movies library folder '%s' does not exist", 'red', $task->{"path"});
    next();
  }
  
  printfv(0, "Organizing movies in '%s'...", $inbox);
  my @files = filesInFolder($inbox,"",1,0,$task->{"cleanup_regex"},$task->{"remove_empty_dir"}eq"true");
  foreach my $file (@files){
    my $match = matchFile($inbox.$file);
    next() if(!$match);
    printfv(0, "-> %s (%i)", $match->{"Title"}, $match->{"Year"});
    $match->{"TitleSortable"} = makeSortable($match->{"Title"});
    moveToLibrary($match, $task->{"path"}, "", $task->{"filename"}, $pattern_map, $task->{"overwrite_strategy"});
    push(@media_added, sprintf("%s (%i) imdb.com/title/%s", $match->{"Title"}, $match->{"Year"}, $match->{"ID"}));
  }
}

sub matchFile
{
  my $file = shift;
     $file =~ m!(.*)\/([^\/]+)\.([0-9a-z]+)$!gi;
  my ($path, $filename, $extension) = ($1, $2, $3);
  printfv(0, "Matching '%s'...", $filename);
  my @matches = findMatches($filename);
  my $choice = -1;
  if(scalar(@matches) > 0){
    if(scalar(@matches) == 1){
      $choice = 1;
    }else{
      printfv(0, "What movie is '%s'?", $filename);
      my $cnt = 1;
      printfvc(0, "(0) None of the listed", 'yellow');
      for my $match (@matches){
        printfv(0, "(%i) %s", $cnt++, matchToString($match));
      }
      while(!($choice >= 0 and $choice <= scalar(@matches))){
        print("Pick one: ");
        $choice = <STDIN>;
      }    
    }
  }
  if($choice > 0){
    my $match = @matches[$choice - 1];
    $match->{"file"} = $file;
    $match->{"extension"} = $extension;
    return $match;
  }else{
    return undef;
  }
  
}

sub findMatches
{
  my $query = shift;
  my @ids = searchImdb($query);
  my @matches = ();
  my $max_results = 4;
     $max_results = $options{"imdb-results"} if(defined $options{"imdb-results"});
  for my $id (@ids){    
    my $match = queryImdb($id);
    push(@matches, $match) if($match);
    last if(scalar(@matches) >= $max_results);
  }
  if(scalar(@matches) > 0){
    return @matches;
  }else{
    printfvc(0, "Cannot match '%s' to any known movie", 'red', $filename);
    return undef;
  }
}

sub searchImdb
{
  my $query = shift;
  printfv(1, "Searching IMDB for '%s'...", $query);
  $web->get("http://www.imdb.com/find?s=tt&q=".uri_escape($query));
  if($web->success()){
    my $links = $web->find_all_links(url_regex => qr/\/title\/tt[0-9]+\/$/);
    my @ids = ();
    for my $link (@{$links}){
      my $url = $link->url();
      if($url =~ m/\/title\/tt([0-9]+)/gi){
        my $exists = 0;
        for my $id (@ids){ $exists = 1 if($id eq $1); }
        if(!$exists){
          push(@ids, $1);
          printfv(1, "Found possible IMDB match with ID %s ~ '%s'", $1, $link->text());
        }
      }
    }
    printfv(1, "IMDB search resulted in %i matches", scalar(@ids));
    return @ids;
  }else{
    printfvc("Error while searching IMDB: %s", 'red', $web->status());
  }
}

sub queryImdb
{
  my $id = shift;
  printfv(1, "Querying IMDB-API for ID %s", $id);
  $web->get("http://www.imdbapi.com/?i=tt".uri_escape($id));  
  if($web->success()){
    my $match = $json->decode($web->content());
    if($match->{"Response"} eq "True"){
      return $match;
    }else{
      # The IMDB API has failed us
      printfvc(1, "Negative IMDB-API parse result: %s, skipping result", 'red', $match->{"Response"});
      return undef;
    }
  }else{
    printfvc("Error while querying IMDB: %s", $web->status());
  }
}

sub matchToString
{
  my $match = shift;
  my $actors = $match->{"Actors"};
     $actors =~ s/,.*$//gi;
  return sprintf("%s (%i) [%s] by '%s' starring '%s'", $match->{"Title"}, $match->{"Year"}, $match->{"Genre"}, $match->{"Director"}, $actors);
}

1;