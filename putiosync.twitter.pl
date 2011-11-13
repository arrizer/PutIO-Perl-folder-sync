my $access_token = $config->{"twitter"}->{"access_token"};
my $secret = $config->{"twitter"}->{"secret"};
my $consumer_key = $config->{"twitter"}->{"consumer_key"};
my $consumer_secret = $config->{"twitter"}->{"consumer_secret"};

if($access_token ne "" and scalar(@media_added) > 0 and !$options{"no-twitter"}){
  my @messages = @media_added;
  use Net::Twitter;

  my $twitter = Net::Twitter->new(
      traits              => [qw/OAuth API::REST/],
      consumer_key        => $consumer_key,
      consumer_secret     => $consumer_secret,
      access_token        => $access_token,
      access_token_secret => $secret,
  );
  for my $message (@messages){
    printfv(1, "Tweeting: %s", $message);
    #$twitter->update($message);
  }
}else{
  printfv(1, "Nothing to tweet");
}

1;