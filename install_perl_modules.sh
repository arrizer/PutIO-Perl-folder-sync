echo "This will install or update the required perl modules for putiosync..."
perl -MCPAN -e 'install WebService::PutIo::Files'
perl -MCPAN -e 'install Getopt::Long'
perl -MCPAN -e 'install Data::Dumper'
perl -MCPAN -e 'install LWP::UserAgent'
perl -MCPAN -e 'install XML::Simple'
perl -MCPAN -e 'install File::Path'
perl -MCPAN -e 'install TVDB::API'