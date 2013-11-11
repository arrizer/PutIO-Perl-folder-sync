my $app_token = $config->{"pushover"}->{"app_token"};
my $user_token = $config->{"pushover"}->{"user_token"};

if(!$options{"no-push"}){
  if($app_token ne "" and $user_token ne '' and scalar(@media_added) > 0){
    my @messages = @media_added;
    for my $message (@messages){
      printfv(1, "Sending push notification: %s", $message);
      LWP::UserAgent->new()->post(
        "https://api.pushover.net/1/messages.json", [
        "token" => $app_token,
        "user" => $user_token,
        "message" => $message,
      ]);
    }
  }else{
    printfv(1, "Nothing to push");
  }
}else{
  printfv(1, "Push disabled by command line option");
}


1;