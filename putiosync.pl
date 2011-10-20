#!/usr/bin/perl

use WebService::PutIo::Files;
use Getopt::Long;
use Data::Dumper;
use LWP::UserAgent;
use XML::Simple;

$| = 1;

my $verbose = 0;
my $autoload = 0;
my $do_delete = 0;

my $config = XMLin("config.xml", ForceArray => ['sync']);

GetOptions("verbose|v" => \$verbose, "a|auto" => \$autoload, "d|delete" => \$do_delete);

my $agent = LWP::UserAgent->new();
my $putio = WebService::PutIo::Files->new('api_key' => $config->{"api_key"}, 
                                          'api_secret' => $config->{"api_secret"});

my @downloadQueue;

foreach my $folder (@{$config->{"sync"}}){
  my $source = $folder->{"remote_path"};
  my $target = $folder->{"local_path"};
  print("Syncing folder '$source' to '$target'...\n");
  if (!(-d $target)) {
	print "The target folder $target doesn't exist!\n";
    next();
  }  
  my $source_id = findPutIoFolderId($source);
  if(!$source_id){
    print("The folder '$source' does not exist!\n");
    next();
  }
  my $res = $putio->list('parent_id', $source_id);
  foreach my $file (@{$res->results}){
    next() if($file->{"type"} eq "folder");
    next() if(-e $target."/".$file->{"name"});
    $file->{"target"} = $target;
    push(@downloadQueue, $file);
  }
}


printf("%s files queued to download\n", $#downloadQueue == -1 ? "No" : ($#downloadQueue + 1));
foreach my $file (@downloadQueue){
  printf("%s\n", $file->{"name"});
}

foreach my $file (@downloadQueue){
  printf("Fetching '%s'\n", $file->{"name"});
  my $url = $file->{"download_url"};
  my $filename = $file->{"target"}."/".$file->{"name"};
  my $succeed = downloadFile($url, $filename);
  if($succeed && $do_delete){
    $putio->delete(id => $file->{"id"});
    print("Deleted the file from put.io!\n")
  }
}

sub findPutIoFolderId{
  findPutIoFolderIdInternal(0, shift, 0); 
}

sub findPutIoFolderIdInternal
{
  my $node = shift;
  my $path = shift;
  my $depth = shift;
  my @path = split('/', $path);

  my $res;
  $res = $putio->list() if($node == 0);
  $res = $putio->list('parent_id' => "$node") if($node != 0);
  
  foreach my $file (@{$res->results}){
    next() if($file->{"type"} ne "folder");
    if($file->{"name"} eq @path[$depth]){
      return $file->{"id"} if($#path == $depth);
      return findPutIoFolderIdInternal($file->{"id"}, $path, $depth + 1);
    }
  }
}

my $download_size;
my $received_size;
my $last_tick;
my $speed_count;
my $speed;
my $avg_speed;
my $avg_speed_q;
my $avg_speed_s;

sub downloadFile
{
  my $url = shift;
  my $filename = shift;
  
  $agent->add_handler(response_header => \&didReceiveResponse);
  $agent->add_handler(response_data => \&didReceiveData);
  $agent->credentials("put.io:80", "Put.io File Space", $config->{"account_name"}, $config->{"account_password"});
  $received_size = 0;
  $bps = 0;
  $avg_speed = 0;
  $avg_speed_s = 0;
  $avg_speed_q = 0;
  $last_tick = time();
  my $response = $agent->get($url, ':content_file' => $filename, ':size_hint' => 10000);
  if(!$response->is_success()){
    print "\rDownload failed: ".$response->status_line()."\n";
	return 0;
  }else{
    print "\rDownload succeeded                                               \n";
	return 1;
  }
}

sub didReceiveResponse
{
  my $response = shift;
  $download_size = $response->header('Content-Length');
}

sub didReceiveData
{
  my($response, $ua, $h, $data) = @_;
  $received_size += length($data);
  $speed_count += length($data);
  my $now = time();
  if($last_tick < $now){
    $speed = $speed_count;
    $speed_count = 0;
    $last_tick = $now;
    $avg_speed_q++;
    $avg_speed_s += $speed;
    $avg_speed = $avg_speed_s / $avg_speed_q;
  }
  print("\r");
  printf("-> %.1f %% (%s of %s, %s/s) %s remaining            ", 
         ($received_size / $download_size) * 100, 
         fsize($received_size), 
         fsize($download_size), 
         fsize($speed), 
         fduration(($download_size - $received_size) / $avg_speed)
        );
}

sub fsize
{
  my $size = shift; 
  return sprintf("%.1f GiB", $size / (1024 ** 3)) if($size > (1024 ** 3));
  return sprintf("%.1f MiB", $size / (1024 ** 2)) if($size > (1024 ** 2));
  return sprintf("%.1f kiB", $size / (1024 ** 1)) if($size > (1024 ** 1));
  return sprintf("%.0f Bytes", $size);
}

sub fduration
{
  my $seconds = shift;
  return sprintf("%.0f days", $seconds / (60 * 60 * 24)) if($seconds >= 60 * 60 * 24);
  return sprintf("%.0f hours", $seconds / (60 * 60)) if($seconds >= 60 * 60);
  return sprintf("%.0f minutes", $seconds / (60)) if($seconds >= 60);
}