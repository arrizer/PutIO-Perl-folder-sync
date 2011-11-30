use URI::Escape;

my $agent = LWP::UserAgent->new();
my $api_key = '5EFCC7790F190138';
my @mirrors = ('thetvdb.com');

sub tvdbSearch
{
  my $seriesName = shift;
  my $data = _xmlRequest('GetSeries.php?seriesname='.uri_escape($seriesName));
  my $xml = XMLin($data, ForceArray => ['Series'], KeyAttr => []);
  return $xml->{'Series'};
}

sub tvdbEpisode
{
  my $seriesName = shift;
  my $season = shift;
  my $episode = shift;
  
  my $matches = tvdbSearch($seriesName);
  my @matches = @$matches;
  return undef if(scalar @matches <= 0);
  my $seriesId = @matches[0]->{"seriesid"};
  return tvdbEpisodeId($seriesId, $season, $episode);
}

sub tvdbEpisodeId
{
  my $seriesId = shift;
  my $season = shift;
  my $episode = shift;
  
  my $data = _apiRequest('series/'.$seriesId.'/default/'.int($season).'/'.int($episode).'/en.xml');
  return undef if(!$data);
  my $xml = XMLin($data);

  return $xml->{"Episode"};
}

sub tvdbSeriesId
{
  my $seriesId = shift;
  
  my $data = _apiRequest('series/'.$seriesId.'/en.xml');
  return undef if(!$data);
  my $xml = XMLin($data);

  return $xml->{"Series"};
}

sub _apiRequest
{
  my $path = shift;
  return _xmlRequest($api.'/'.$api_key.'/'.$path);
}

sub _xmlRequest
{
  my $path = shift;
  my $domain = @mirrors[0];
  my $url = 'http://'.$domain.'/api/'.$path;
  my $response = $agent->get($url);
  if($response->is_success()){
    return $response->decoded_content();
  }else{
    printfv(1, 'TheTVDB API request "'.$url.'" failed: '.$response->status_line());
    return undef;
  }
}

1;