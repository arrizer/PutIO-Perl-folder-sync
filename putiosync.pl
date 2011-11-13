#!/usr/bin/env perl
$| = 1; # Disable output caching

use WebService::PutIo::Files;
use Getopt::Long;
use Data::Dumper;
use LWP::UserAgent;
use XML::Simple;
use File::Path qw(make_path);
use File::Basename;
use Term::ANSIColor;
use Term::ReadKey;
use Cwd 'abs_path';
use utf8;
use warnings;
use strict;

my $windows = $^O =~ /Win32/i;
$SIG{INT} = \&catchSigInt;

BEGIN {
	if($windows){
    require Win32::Console::ANSI;
		import Win32::Console::ANSI;
		require Win32::File;
		import Win32::File;
	}
}

my $version = '0.5.1';
our $mypath = abs_path(File::Basename::dirname(__FILE__));
our $verbosity = 0; # -1 = quiet, 0 = normal, 1 = verbose, 2 = debug
my $config_file = $mypath."/config.xml";
my $download_temp_dir = ".putiosync-downloading";
my $pid_file = "./putiosync.pid";

require $mypath.'/utils.pl';

# Process command line flags
our %options = ();
processCommandLine();

# Read config XML
our $config = XMLin($config_file, ForceArray => ['sync', 'tvshows', 'movies']);

# Initialise HTTP and putio clients
my $agent = LWP::UserAgent->new();
   $agent->add_handler(request_prepare => \&prepareRequest);
   $agent->add_handler(response_header => \&didReceiveResponse);
   $agent->credentials("put.io:80", "Put.io File Space", $config->{"account_name"}, $config->{"account_password"});
my $putio = WebService::PutIo::Files->new('api_key' => $config->{"api_key"}, 
                                          'api_secret' => $config->{"api_secret"});

our @media_added = ();
if(!$options{'no-sync'}){
  my @downloadQueue = queueSyncItems();
  downloadFiles(\@downloadQueue) if(!$options{'dry'} and $#downloadQueue > -1);
}
runExtensions() if(!$options{'no-extensions'});
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
      $newQueue[$i]->{"delete_source"} = $delete_source;
      $newQueue[$i]->{"target_folder"} = $target;
    }
    push(@downloadQueue, @newQueue);
  }
  printfv(0, "%s files queued to download", $#downloadQueue == -1 ? "No" : ($#downloadQueue + 1));
  foreach my $file (@downloadQueue){
    printfvc(0, "%s", 'cyan', $file->{"name"});
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
      if(scalar($file->{"size"}) == $stat[7]){
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
    if($file->{"name"} eq $path[$depth]){
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
  	if ($windows){
      # Disabled this temporarily as it does not compile strict!
      #Win32::File::SetAttributes($file->{"target_folder"}.'/'.$download_temp_dir, DIRECTORY | HIDDEN);
    }
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
    
  ($download_size, $received_size, $avg_speed, $avg_speed_s, $avg_speed_q, $speed_count, $speed, $byte_offset, $http_status) = (0,0,0,0,0,0,0,0,0);
  if(-e $temp_filename and !$options{'no-resume'}){
    my @stat = stat($temp_filename);
    if($expected_size > $stat[7]){
      $byte_offset = $stat[7];
      $received_size = $stat[7];
    }
  }
  open DOWNLOAD, ($byte_offset > 0) ? ">>" : ">", $temp_filename or die "Unable to create download file: $!";
  binmode DOWNLOAD;
  $last_tick = time();
  my $response = $agent->get($url, ':read_size_hint' => (2 ** 14), ':content_cb' => \&didReceiveData);
  close DOWNLOAD;
  my @stat = stat($temp_filename);
  my $actual_size = $stat[7];
  
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
  my ($data, $cb_response, $protocol) = @_;
  #my($response, $ua, $h, $data) = @_;
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
    printf("-> %.1f %% (%s of %s, %s/s) %s      ", 
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

sub processCommandLine
{
  $options{"v"} = 0;
  $options{"q"} = 0;
  $options{"h"} = 0;
  $options{"config"} = "";
  $options{"no-sync"} = 0;
  $options{"dry"} = 0;
  $options{"no-extensions"} = 0;
  $options{"n"} = 0;
  $options{"no-resume"} = 0;
  $options{"pid"} = "";
  $options{"no-color"} = 0;
  
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
    "pid=s",
    "no-color", 
    "imdb-results=i",
    "no-twitter"
  );
  GetOptions(\%options, @flags);
  $verbosity = 1 if($options{'v'});
  $verbosity = -1 if($options{'q'});
  $config_file = $options{'config'} if($options{'config'} ne "");
  $pid_file = $options{'pid'} if($options{'pid'} ne "");
  $ENV{'ANSI_COLORS_DISABLED'} = 1 if($options{'no-color'});
  printHelp() if($options{'h'});
}

sub printHelp
{
printfvc(0, '
 ______   _    _  _______ _____  ______   ______  __    _   ______   ______ 
| |  | \ | |  | |   | |    | |  / |  | \ / |      \ \  | | | |  \ \ | |     
| |__|_/ | |  | |   | |    | |  | |  | | \'------.  \_\_| | | |  | | | |     
|_|      \_|__|_|   |_|   _|_|_ \_|__|_/  ____|_/  ____|_| |_|  |_| |_|____ 

Version %s
', 'blue', $version);
printfvc(0, "Copyright by Matthias Schwab (putiosync\@matthiasschwab.de)
Feature requests and bugs? Please report to:
    https://github.com/arrizer/PutIO-Perl-folder-sync/issues", 'cyan');
print("
Automate download of files and folders from the put.io webservice.
Files from folders specified in the configuration file will be downloaded to the
specified target on the local disk. See the comments in the config file template
for details about the configuration.

  Usage: $0 [options]

Options: -v  --verbose          Show more detailed status information
         -q  --quiet            No output whatsoever
         -h  --help             Show this help screen and exit
         -n  --non-interactive  Don't ask anything
             --config <file>    Use specific config file (default is config.xml)
             --dry              Dry run (nothing is downloaded, moved or changed)
             --no-sync          Skip syncing (only run extension scripts)
             --no-extensions    Don't run any extension scripts after sycning
             --no-delete        Never delete files from put.io
             --no-resume        Redownload partially received files instead of
                                resuming the download
             --pid <file>       PID file location (default = ./putiosync.pid)
             --no-color         Disables colored output
             --imdb-results <n> Display n suggestions for movies (default is 4)
             --no-twitter       Don't twitter anything
");
  exit();
}

sub runExtensions
{
  opendir DIR, $mypath;
  my @extensions = ();
  while (my $file = readdir(DIR)) {
    next() if ($file !~ m/^putiosync\.(.*?)\.pl$/gi);
    push(@extensions, $1);
	}
	closedir DIR;
	for my $extension (@extensions){
    printfv(1, "Running extension '%s'", $extension);
    require $mypath."/putiosync.".$extension.".pl";
    printfv(1, "Extension '%s' did finish running", $extension);
	}
}

sub catchSigInt
{
  printfvc(0, "Catched termination signal", 'red bold');
  exit();
}