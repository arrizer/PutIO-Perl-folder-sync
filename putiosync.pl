#!/usr/bin/perl
$| = 1;

use WebService::PutIo::Files;
use Getopt::Long;
use Data::Dumper;
use LWP::UserAgent;
use XML::Simple;
use File::Path qw(make_path);
use File::Basename;
use Term::ANSIColor;
use Cwd 'abs_path';

my $version = '0.4';
my $verbosity = 0; # -1 = quiet, 0 = normal, 1 = verbose, 2 = debug
our $mypath = abs_path(File::Basename::dirname(__FILE__));
my $config_file = $mypath."/config.xml";
my $download_temp_dir = ".putiosync-downloading";
my $pid_file = "./putiosync.pid";

# Process command line flags
our %options = ();
processCommandLine();

# Read config XML
our $config = XMLin($config_file, ForceArray => ['sync', 'tvshows']);

# Initialise HTTP and putio clients
my $agent = LWP::UserAgent->new();
   $agent->add_handler(request_prepare => \&prepareRequest);
   $agent->add_handler(response_header => \&didReceiveResponse);
   $agent->add_handler(response_data => \&didReceiveData);
   $agent->credentials("put.io:80", "Put.io File Space", $config->{"account_name"}, $config->{"account_password"});
my $putio = WebService::PutIo::Files->new('api_key' => $config->{"api_key"}, 
                                          'api_secret' => $config->{"api_secret"});

if(!$options{'no-sync'}){
  my @downloadQueue = queueSyncItems();
  # Present queued items
  printfv(0, "\n%s files queued to download", $#downloadQueue == -1 ? "No" : ($#downloadQueue + 1));
  foreach my $file (@downloadQueue){
    printfvc(0, "%s", 'cyan', $file->{"name"});
  }
  printfv(0, "\n");
  
  if($#downloadQueue > -1){
    if(!$options{'dry'}){
      downloadFiles(\@downloadQueue);
    }else{
      printfvc(0, "Downloading nothing because dry run is enabled", 'red');
    }
  }
}
if(!$options{'no-extensions'}){
  # Run extensions
  opendir DIR, $mypath;
  while (my $file = readdir(DIR)) {
    next() if ($file !~ m/^putiosync\..*?\.pl$/gi);
    my $script = $mypath."/".$file;
    require $script;
		printfv(1, "Running extension '%s'", $script);
	}
	closedir DIR;
}

exit();











sub queueSyncItems
{
  my @downloadQueue;
  # Queue downloads
  foreach my $sync_item (@{$config->{"sync"}}){
    my $source = $sync_item->{"remote_path"};
    my $target = $sync_item->{"local_path"};
    my $recursive = $sync_item->{"recursive"} eq 'true';
    my $delete_source = $sync_item->{"delete"} eq 'true';
    $source =~ s/(^\/|\/$)//gi; # Trim leading and trailing slashes from the source path
    printfvc(0, "Syncing folder '%s' to '%s'...", 'yellow', $source, $target);
    if (!(-d $target)) {
    	printfvc(0, "The target folder '%s' does not exist!", 'red', $target);
      next();
    }
    my @newQueue = queuePutIoFolderPath($source, $target, $recursive);
    for(my $i = 0; $i < scalar(@newQueue); $i++){
      @newQueue[$i]->{"delete_source"} = $delete_source;
      @newQueue[$i]->{"target_folder"} = $target;
    }
    push(@downloadQueue, @newQueue);
  }
  
  return @downloadQueue;
}

sub queuePutIoFolderPath
{
  my $source = shift;
  my $target = shift;
  my $recursive = shift or 0;
  my $source_id = findPutIoFolderId($source);
  if(!$source_id){
    printfvc(0, "The folder '$source' was not found on put.io!", 'red');
    return 0;
  }
  
  return queuePutIoFolder($source_id, $target, $recursive);
}

sub queuePutIoFolder
{
  my $source_id = shift;
  my $target = shift;
  my $recursive = shift or 0;
  my @queue = ();

  my $res = $putio->list('parent_id', $source_id);
  foreach my $file (@{$res->results}){
    if($file->{"type"} eq "folder"){
      next() if(!$recursive);
      push(@queue, queuePutIoFolder($file->{"id"}, $target."/".$file->{"name"}, 1));
      next();
    }
    if(-e $target."/".$file->{"name"}){
      my @stat = stat($target."/".$file->{"name"});
      if(scalar($file->{"size"}) == @stat[7]){
        printfv(1, "File '%s' already exists and will be skipped", $file->{"name"});
        next();
      }else{
        printfv(1, "File '%s' exists but has a different size. Will be redownloaded", $file->{"name"});
      }
    }
    $file->{"target"} = $target;
    push(@queue, $file);
  }
  return @queue;
}

sub findPutIoFolderId
{
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

sub downloadFiles
{
  # Downloads item from a queue
  my @downloadQueue = @{shift()};
  my $cnt = 0;
  foreach my $file (@downloadQueue){
    $cnt++;
    printfv(0, "Fetching '%s' [%i of %i]", $file->{"name"}, $cnt, $#downloadQueue + 1);
    my $url = $file->{"download_url"};
    make_path($file->{"target"});
    make_path($file->{"target_folder"}.'/'.$download_temp_dir);
    my $filename = $file->{"target"}."/".$file->{"name"};
    my $temp_filename = $file->{"target_folder"}.'/'.$download_temp_dir.'/'.$file->{"name"};
    my $succeeded = downloadFile($url, $filename, $temp_filename, $file->{"size"});
    if($succeeded and $file->{"delete_source"}){
      $putio->delete(id => $file->{"id"});
      printfv(1, "Deleted the file on put.io");
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
my $byte_offset;
my $http_status;

sub downloadFile
{
  my $url = shift;
  my $filename = shift;
  my $temp_filename = shift;
  my $expected_size = shift;
    
  ($download_size, $received_size, $bps, $avg_speed, $avg_speed_s, $avg_speed_q, $speed_count, $speed, $byte_offset, $http_status) = (0,0,0,0,0,0,0,0,0,0);
  if(-e $temp_filename and !$options{'no-resume'}){
    my @stat = stat($temp_filename);
    if($expected_size > @stat[7]){
      $byte_offset = @stat[7];
      $received_size = @stat[7];
    }
  }
  open DOWNLOAD, ($byte_offset > 0) ? ">>" : ">", $temp_filename or die "Unable to create download file: $!";
  binmode DOWNLOAD;
  $last_tick = time();
  my $response = $agent->get($url, ':read_size_hint' => (2 ** 14));
  close DOWNLOAD;
  my @stat = stat($temp_filename);
  my $actual_size = @stat[7];
  
  if(!$response->is_success()){
    printfvc(0, "\rDownload failed: %s", 'red', $response->status_line());
    return 0;
  }elsif($actual_size != $expected_size){
    printfvc(0, "\rDownloaded file does not have expected size (%s vs. %s)", 'red', $actual_size, $expected_size);
    return 0;
  }else{
    rename $temp_filename, $filename;
    printfvc(0, "\rDownload succeeded                                                           ", 'green');
  	return 1;
  }
}

sub prepareRequest
{
  my $request = shift;
  $request->header('Range', 'bytes='.$byte_offset.'-') if($byte_offset > 0);
  #print Dumper($request);
  return $request;
}

sub didReceiveResponse
{
  my $response = shift;
  #print Dumper $response;
  $http_status = $response->code();
  $download_size = int($response->header('Content-Length')) + $byte_offset;
}

sub didReceiveData
{
  my($response, $ua, $h, $data) = @_;
  my $data_size = scalar(length($data));
  $received_size += $data_size;
  $speed_count += $data_size;
  my $now = time();
  if($last_tick < $now){
    $speed = $speed_count;
    $speed_count = 0;
    $last_tick = $now;
    $avg_speed_q++;
    $avg_speed_s += $speed;
    $avg_speed = $avg_speed_s / $avg_speed_q;
  }
  print("\r") if($verbosity >= 0);
  #print "Chunk = $data_size ";
  if($download_size > 0 and $http_status eq "200" or $http_status eq "206"){
    print DOWNLOAD $data;
    printf("-> %.1f %% (%s of %s, %s/s) %s                       ", 
      ($received_size / $download_size) * 100, 
      fsize($received_size), 
      fsize($download_size), 
      fsize($speed), 
      $avg_speed_q > 3 ? fduration(($download_size - $received_size) / $avg_speed)." remaining" : ""
   ) if($verbosity >= 0);
  }else{
    printf("-> Initiating transfer...                                 ") if($verbosity >= 0);
  }
  return 1;
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
  return sprintf("%.0f seconds", $seconds) if($seconds < 60);
  return sprintf("a few seconds", $seconds) if($seconds < 7);
}

sub printfv
{
  # Prints a line to the console if the $level is below or equal the current script verbosity
  my ($level, $format, @parameters) = @_;
  printf($format."\n", @parameters) if($level <= $verbose);
}

sub printfvc
{
  # Prints a colored line
  my ($level, $format, $color, @parameters) = @_;
  print color $color;
  printf($format, @parameters) if($level <= $verbose);
  print color 'reset';
  print("\n");
}

sub processCommandLine
{
  my @flags = (
    "v|verbose", 
    "q|quiet", 
    "h|help", 
    "config=s", 
    "no-sync", 
    "dry", 
    "no-extensions", 
    "n|non-interactive", 
    "no-resume", 
    "pid=s"
  );
  GetOptions(\%options, @flags);
  $verbosity = 1 if($options{'v'});
  $verbosity = -1 if($options{'q'});
  $config_file = $options{'config'} if($options{'config'} ne "");
  $pid_file = $options{'pid'} if($options{'pid'} ne "");
  printHelp() if($options{'h'});
}

sub printHelp
{
print("
PutIO folder sync - Version $version
================================================================================
Copyright by Matthias Schwab (putiosync\@matthiasschwab.de)
Feature requests and bugs? Please report to:
    https://github.com/arrizer/PutIO-Perl-folder-sync/issues

Automate download of files and folders from the put.io webservice.
Files from folders specified in the configuration file will be downloaded to the
specified target on the local disk. See the comments in the config file template
for details about the configuration.

Usage:   $0 [options]

Options: -v  --verbose         Show more detailed status information
         -q  --quiet           No output whatsoever
         -h  --help            Show this help screen and exit
         -n  --non-interactive Don't ask anything
             --config <file>   Use specific config file (default is config.xml)
             --dry             Dry run (nothing is downloaded, just checking)
             --no-sync         Skip syncing (only run extension scripts)
             --no-extensions   Don't run any extension scripts after sycning
             --no-delete       Never delete files from put.io
             --no-resume       Redownload partially received files instead of
                               resuming the download
             --pid <file>      PID file location (default = ./putiosync.pid)
             
Extensions
----------

TV Show organizer:
       Moves TV shows from an inbox folder to organized show and season folders
       and renames them. Title matching is done via thetvdb.com.
       Add <tvshows> tags to the config file to configure the this extension.
       See comments in the config template for details.
       
Movie organizer:
       Not yet implemented!
");
  exit();
}