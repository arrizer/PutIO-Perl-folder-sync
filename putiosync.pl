#!/usr/bin/perl

use WebService::PutIo::Files;
use Getopt::Long;
use Data::Dumper;
use LWP::UserAgent;
use XML::Simple;
use File::Path qw(make_path);
use Cwd 'abs_path';

our $mypath = abs_path($0); $mypath =~ s![^\/]+$!!gis;

$| = 1;

my $verbose = 0;
my $do_delete = 0;
my $no_sync = 0;
my $show_help = 0;
my $dry_run = 0;
my $no_extensions = 0;
my $config_file = $mypath."/config.xml";
my $version = "0.4";

# Process command line flags
GetOptions("verbose|v" => \$verbose,
           "d|delete" => \$do_delete,
           "h|help" => \$show_help,
           "config=s" => \$config_file,
           "no-sync" => \$no_sync,
           "d|dry" => \$dry_run,
           "no-extensions" => \$no_extensions);

our $config = XMLin($config_file, ForceArray => ['sync', 'tvshows']);

my $agent = LWP::UserAgent->new();
my $putio = WebService::PutIo::Files->new('api_key' => $config->{"api_key"}, 
                                          'api_secret' => $config->{"api_secret"});

printHelp() if($show_help);

if(!$no_sync){
  my @downloadQueue = queueSyncItems();
  # Present queued items
  printfv(0, "\n%s files queued to download:", $#downloadQueue == -1 ? "No" : ($#downloadQueue + 1));
  foreach my $file (@downloadQueue){
    printfv(0, "%s", $file->{"name"});
  }
  print("\n");
  
  if($#downloadQueue > -1){
    if(!$dry_run){
      downloadFiles(\@downloadQueue);
    }else{
      printfv(0, "Downloading nothing because dry run is enabled");
    }
  }
}
if(!$no_extensions){
  # Run extensions
  my @extensions = <"$mypath/putiosync.*.pl">;
  for my $script (@extensions){
    printfv(1, "Running extension '%s'", $script);
    require $script;
  }
}












sub queueSyncItems
{
  my @downloadQueue;
  # Queue downloads
  foreach my $sync_item (@{$config->{"sync"}}){
    my $source = $sync_item->{"remote_path"};
    my $target = $sync_item->{"local_path"};
    my $recursive = $sync_item->{"recursive"} eq 'true';
    $source =~ s/(^\/|\/$)//gi; # Trim leading and trailing slashes from the source path
    printfv(0, "Syncing folder '%s' to '%s'...", $source, $target);
    if (!(-d $target)) {
    	printfv(0, "The target folder '%s' does not exist!", $target);
      next();
    }
    push(@downloadQueue, queuePutIoFolder($source, $target, $recursive));
  }
  
  return @downloadQueue;
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
    my $filename = $file->{"target"}."/".$file->{"name"};
    my $succeed = downloadFile($url, $filename);
    if($succeed and $do_delete){
      $putio->delete(id => $file->{"id"});
      printfv(1, "Deleted the file on put.io");
    }
  }
}

sub queuePutIoFolder
{
  my $source = shift;
  my $target = shift;
  my $recursive = shift or 0;
  my @queue = ();
  
  my $source_id = findPutIoFolderId($source);
  if(!$source_id){
    printfv(0, "The folder '$source' was not found on put.io!");
    return 0;
  }

  my $res = $putio->list('parent_id', $source_id);
  foreach my $file (@{$res->results}){
    if($file->{"type"} eq "folder"){
      next() if(!$recursive);
      push(@queue, queuePutIoFolder($source."/".$file->{"name"}, $target."/".$file->{"name"}, 1));
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
  ($download_size, $received_size, $bps, $avg_speed, $avg_speed_s, $avg_speed_q, $speed_count, $speed) = (0,0,0,0,0,0,0,0);
  $last_tick = time();
  my $response = $agent->get($url, ':content_file' => $filename, ':read_size_hint' => (2 ** 14));
  if(!$response->is_success()){
    printfv(0, "\rDownload failed: %s", $response->status_line());
    return 0;
  }else{
    printfv(0, "\rDownload succeeded                                                     ");
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
  print("\r");
  #print "Chunk = $data_size ";
  if($download_size > 0){
    printf("-> %.1f %% (%s of %s, %s/s) %s remaining     ", 
           ($received_size / $download_size) * 100, 
           fsize($received_size), 
           fsize($download_size), 
           fsize($speed), 
           fduration(($download_size - $received_size) / $avg_speed)
          );
  }else{
    printf("-> Initiating transfer...                           ");
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

sub printHelp
{
  print("
PutIO folder sync - Version $version
################################################################################
Copyright by Matthias Schwab (putiosync\@matthiasschwab.de)
Feature requests and bugs? Please report to:
    https://github.com/arrizer/PutIO-Perl-folder-sync/issues

Automate download of files and folders from the put.io webservice.
Files from folders specified in the configuration file will be downloaded to the
specified target on the local disk. See the comments in the config file template
for details about the configuration.

Usage:   $0 [options]

Options: -v  --verbose        Show more detailed status information
         -d  --delete         Delete files on put.io after successful download
         -h  --help           Show this help screen and exit
             --config <file>  Use specific config file (default is config.xml)
         -d  --dry            Dry run (nothing is downloaded, just checking)
             --no-sync        Skip syncing (only run extension scripts)
             --no-extensions  Don't run any extension scripts after sycning
             
Extensions
----------

TV Show organizer:
       Moves tv shows from an inbox folder to organized show and season folders
       and renames them. Title matching is done via thetvdb.com.
       Add <tvshows> tags to the config file to configure the this extension.
       See comments in the config template for details.
       
Movie organizer:
       Not yet implemented!
");
  exit();
}