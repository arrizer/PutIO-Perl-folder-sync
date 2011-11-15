my $access_token = $config->{"twitter"}->{"access_token"};
my $secret = $config->{"twitter"}->{"secret"};
my $consumer_key = $config->{"twitter"}->{"consumer_key"};
my $consumer_secret = $config->{"twitter"}->{"consumer_secret"};

if(!$options{"no-twitter"}){
  if($access_token ne "" and scalar(@media_added) > 0){
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
      $twitter->update($message);
    }
  }else{
    printfv(1, "Nothing to tweet");
  }
}else{
  printfv(1, "Twitter disabled by command line option");
}


1;