my $to = $config->{"mail"}->{"to"};
my $from = $config->{"mail"}->{"from"};
my $subject = $config->{"mail"}->{"subject"};
my $server = $config->{"mail"}->{"server"};

sub _getMailMx
{
	my $email = shift;
	$email =~ /.*\@([^>]+).*/;
	my $mail_domain = $1;
	$res = Net::DNS::Resolver->new;
	@mx = mx($res, $mail_domain);
	if (@mx) {
	  return $mx[0]->exchange;
	}
	else {
	  print "can't find MX records for $mail_domain: ", $res->errorstring, "\n";
	} 	
}

sub _sendMail
{
	my ($from, $to, $subject, $body, $server, $is_html) = @_;
	
	my %mail = (
         from => $from,
         to => $to,
         subject => $subject,
		 'body' => $body
	);
	
	if ($server)
	{
		$mail{'server'} = $server;
	}
	else
	{
		$mail{'server'} = _getMailMx($to);
	}	
	if ($is_html)
	{
		$mail{'content-type'} = 'text/html; charset="utf-8"';
	}
	
	if (sendmail(%mail)) {
		return 1;
	}
	else {
		printfv(1, "\n!Error sending mail:\n$Mail::Sendmail::error\n");
		return 0;
	}
}

if($to ne "" and scalar(@media_added) > 0 and !$options{"no-mail"}){
	my @messages = @media_added;
  
	use Mail::Sendmail;
	use Net::DNS;
	
	my $downloaded = join("\n",@messages);
	
	;

	if (_sendMail($from,$to,$subject,$downloaded,$server,0))
	{
	    printfv(1, "Mail sent to: ", $to);
	}
	else
	{
		printfv(1, "Error sending mail.");
	}
}

1;