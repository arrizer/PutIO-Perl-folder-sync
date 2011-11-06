echo "This will install or update the required perl modules for putiosync..."
sudo perl -MCPAN -e 'install WebService::PutIo::Files'
sudo perl -MCPAN -e 'install Getopt::Long'
sudo perl -MCPAN -e 'install Data::Dumper'
sudo perl -MCPAN -e 'install LWP::UserAgent'
sudo perl -MCPAN -e 'install LWP::Protocol::https'
sudo perl -MCPAN -e 'install XML::Simple'
sudo perl -MCPAN -e 'install File::Path'
sudo perl -MCPAN -e 'install TVDB::API'