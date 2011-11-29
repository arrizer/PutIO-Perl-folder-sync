use IO::Null;

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
  my ($level, $format, @parameters) = @_;
  printfvc($level, $format, $level >= 1 ? 'blue' : '', @parameters);
}

sub printfvc
{
  # Prints a colored line
  my ($level, $format, $color, @parameters) = @_;
  
  return if($level > $verbosity);
  print color $color if($color ne '');
  my $string = sprintf($format, @parameters);
  if($string !~ m/\n/gis){
    ($wchar, $hchar, $wpixels, $hpixels) = GetTerminalSize();
    $string = substr($string, 0, $wchar);
    printf("%-".($wchar-1)."s", $string);
  }else{
    print($string);
  }
  
  print color 'reset';
  print("\n");
}

sub filesInFolder
{
  my $path = shift;
  my $subdir = shift or "";
  my $recursive = shift or 1;
  my $allowed_extensions = shift;
     $allowed_extensions = ['mov', 'avi', 'mp4', 'mpeg4', 'mkv', 'mts', 'ts'] if(!$allowed_extensions);
  my $extensions_regexp = join('|', @{$allowed_extensions});
  my @files = ();
  opendir DIR, $path.'/'.$subdir;
  foreach my $file (readdir DIR){
    next() if($file =~ m/^\./gi);
    my $file_abs = $path.'/'.$subdir.'/'.$file;
    if(-d $file_abs){
      push(@files, filesInFolder($path, $subdir."/".$file));
      next();
    }elsif($file =~ m/\.($extensions_regexp)$/gi){
      push(@files, $subdir.'/'.$file);
    }
  }
  closedir DIR;
  return @files;
}

my $oldfh;
my $null = IO::Null->new();

sub shutup
{
  my $silence = shift;
  if($silence){
    $oldfh = select($null);
  }else{
    select($oldfh);
  } 
}

sub makeSortable
{
  my $title = shift;

  if($title =~ m!^(the|der|die|das|les|le|la|los|a|an) (.*)$!gis){
    $title = $2.', '.$1;
  }
  return $title;
}

sub expandPlaceholders
{
  my $match = shift;
  my $pattern = shift;
  my $pattern_map = shift;
  
  foreach my $key (keys %{$pattern_map}){
    my $value = $match->{$pattern_map->{$key}};
    $pattern =~ s!$key!$value!gi;
  }
  return $pattern;
}

sub moveToLibrary
{
  my $match = shift;
  my $target = shift;
  my $folder_pattern = shift;
  my $file_pattern = shift;
  my $pattern_map = shift;
  my $overwrite_strategy = shift;
  
  my $folder = expandPlaceholders($match, $folder_pattern, $pattern_map);
  my $file = expandPlaceholders($match, $file_pattern, $pattern_map);
  
  # Remove invalid chacracters from filename
  $file =~ s/[<>:"\/\\|\?\*]//g;
  
  my @existing = existingFilesInLibrary($target.'/'.$folder, $file);
  if(scalar(@existing) == 1){
    my $existing = @existing[0];
    my @stat_new = stat($match->{"file"});
    my @stat_old = stat($existing);
    if($overwrite_strategy eq "always"){
      printfvc(0, "The file is already in the library and will be overwritten.", 'green');
    }
    elsif($overwrite_strategy eq "ask"){ 
      return if($options{"n"});
      my $choice = "";
      while($choice !~ m/^(y|n)/gi){
        printf("File already there (new: %s, old: %s). Overwrite? [y/n]: ", fsize(@stat_new[7]), fsize(@stat_old[7]));
        $choice = <STDIN>;
      }
      return if($choice ne "y\n");
    }
    elsif($overwrite_strategy eq "bigger"){
      if(@stat_new[7] > @stat_old[7]){
        printvc(0, "A smaller file is already present in the library and will be overwritten.", 'green');
      }else{
        printvc(0, "A bigger or equally sized file is already present in the library. Skipping.", 'red');
        return;
      }
    }else{ #aka 'never'
      printfvc(0, "The file is already in the library. Skipping.", 'red');
      return;
    }
  }elsif(scalar(@existing) > 1){
    printfvc(0, "More than one similar files are already in the library!", 'red');
  }
  for my $existing (@existing){
    unlink($existing) or die('Unable to remove file "'.$existing.'" from library: '.$!);
  }
  my $destination = $target.'/'.$folder.'/'.$file.'.'.$match->{"extension"};
  make_path($target.'/'.$folder.'/');
  rename $match->{"file"}, $destination or die('Unable to move file "'.$match->{"file"}.'" to "'.$destination.'": '.$!);
  return 1;
}

sub existingFilesInLibrary
{
  my $folder = shift;
  my $name = shift;
  opendir DIR, $folder;
  my @matches = ();
  while(my $file = readdir DIR){
    if($file =~ m/(.*)\..*$/gi){
      push(@matches, $folder.'/'.$file) if($1 eq $name);
    }
  }
  closedir DIR;
  return @matches;
}

sub pidBegin
{
  my $pidfile = shift;
  #die $pidfile;
	my $override = shift or 0;
	# Check if another instance of the process is already running
	if(-e $pidfile){
		open PIDFILE, "<".$pidfile;
		my $pid = <PIDFILE>;
		close PIDFILE;
		# Paw the other process to see if it moves
		my $exists = kill 0, $pid;
		return $pid if(!$override and $exists);
		if($override and $exists){
		  # It's alive! Kill it!
			my $res = kill 15, $pid;
			if($res eq 1){
				printfvc(0, "Terminated other instances process!", 'green bold');
			}else{
				printfvc(0, "Could not terminate other instance!", 'red bold');
				return $pid;
			}
		}
	}
	open PIDFILE, ">".$pidfile;
	print PIDFILE $$;
	close PIDFILE;
	return 0;
}

sub pidFinish
{
  my $pidfile = shift;
	unlink $pidfile;
}


1;