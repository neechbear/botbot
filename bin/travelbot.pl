#!/usr/local/bin/perl
######################################################################
# EH GagBot, by Nick Waterman of Nilex
# all rights wronged, all wrongs reserved
######################################################################

$| = 1;

$botver = "0.01";

$serv_host = $ARGV[0] || "eh.org";
$serv_port = $ARGV[1] || 90210;
$botname   = $ARGV[2] || "TravelBot";
$botpw     = $ARGV[3] || "botbotbot";
# $botcomment = "perl $botname $botver. Try >$botname help\n";

use Socket;
use XML::Simple;
#use Data::Dumper;

&loadENT("/home/system/cps/travelnews/en/dtd/locML.ent");
&loadENT("/home/system/cps/travelnews/en/dtd/ptiML.ent");
&loadENT("/home/system/cps/travelnews/en/dtd/rtmML.ent");

sub coneh;
sub fakeconeh;
sub logineh;
sub dotell;
sub loopcheck;

######################################################################

&loadXML;
coneh or die "can't connect to EH";

print "# connection set up.\n";

logineh;
print "# EH ready. $botname ready. entering main loop.\n";
print "# -------------------------------------------------------------------\n";

$lasttime = $thissec = 0;

while (<EH>) {
    chomp;
#    print "$_\n";
    
# accept tells, and try to do something with them.
    if (/^TELL (\S+)\s*>\s*(.*)/) {
        loopcheck;
        dotell($1,$2);
# try to preserve the bot group name
    } elsif (/^GNAME (\S+) has changed the group name to Bots-R-Us$/i) {
        print "# group name OK\n";
    } elsif (/^GNAME (\S+) has changed the group name/i) {
        print "# bad group name - $1 did it\n";
        loopcheck;
        print EH ".evict $1\n";
        print EH ".gname Bots-R-Us\n";
# try to stay in group bots-r-us.
    } elsif (/^EVICT You have been /) {
        print "# I was evicted!\n";
        loopcheck;
        print EH ".group Bots-R-Us\n";
# don't idle out.
    } elsif (/^IDLEWARN /) {
        print "# idlewarn\n";
        loopcheck;
        print EH ".-\n";
# when a minute ticks by, look for new XML files
    } elsif (/^TIME /) {
      &loadXML;
# at closedown, try to reconnect.
    } elsif (/^CLOSEDOWN /) {
        print "# closedown\n";
        close EH;
        sleep 60;
        print "# re-running...\n";
        exec $0, @ARGV;
        die "couldn't re-run myself";
    } elsif (/^(EXAMINE|MARK|LOOK|LOOKHDR|GROUPHDR|DONETELL) /) {
        # ignore.
    } else {
        print "$_\n";
    }
}

exit;

sub coneh {
    # return fakeconeh @_;
    print "# Trying to connect to EH...\n";
    $paddr = sockaddr_in($serv_port, inet_aton($serv_host));
    socket(EH, PF_INET, SOCK_STREAM, getprotobyname('tcp'))
        or return 0;
    connect(EH, $paddr) or return 0;
    
    select (EH); $|=1;
    select (STDOUT); $|=1;
    return 1;
}

sub fakeconeh {
    open(EH, "fakeh.pl |") or die "can't run fake EH";
    select (EH); $|=1;
    select (STDOUT); $|=1;    
    return 1;
}

sub logineh {
    print "# Waiting for login prompt.\n";
    while (<EH>) {
        chomp;
#       print "$_\n";
        last if /^\+\+\+ Please enter your name/;
    }
    
    print "# Going into client mode\n";
    print EH ".set term client\n";
    while (<EH>) {
        chomp;
#       print "$_\n";
        last if /^DONE /;
    }
    
    print "# Logging on\n";
    print EH "$botname $botpw\n";
    while (<EH>) {
        chomp;
#       print "$_\n";;
        if (/^ALREADYON You are already logged/) {
            print "# already on!\n";
            print EH "*$botname $botpw\n";
        }
        last if /^CONNECT You have connected/;
    }
    
    if ($botcomment) { print EH ".comment $botcomment\n"; }

    print "# setting timewarn, and seeing who's on\n";
    print EH ".set timewarn 5\n";
    
    return;
}

sub dotell {
    my ($user, $stuff) = @_;
    my $acc = $loa{lc($user)};
    
# ignore myself and other bots.
    if ($user =~ /bot$/i) {
        print "# $user : $stuff\n";
        print "# loop?\n";
# user commands - help, version
    } elsif ($stuff =~ /^help/i) {
        print "# $user needs help\n";
        print EH ">$user I am a travelbot. I provide travel information " .
                 "from the BBC. Commands available:\n";
        print EH ">$user help, version: hopefully obvious\n";
        print EH ">$user [all] <road>: provides information about that road\n";
        print EH ">$user [all] area <area>: provides information about that area (town or county name)\n";
        
    } elsif ($stuff =~ /^version/i) {
        print "# $user asks version\n";
        print EH ">$user bot version $botver by Slimey\n";
    } elsif ($stuff =~ /^(all )?([mab]\d+)/i) {
	&roadinfo($user, $1, $2)
    } elsif ($stuff =~ /^(all )?road (\S+)/i) {
	&roadinfo($user, $1, $2)
    } elsif ($stuff =~ /^(all )?area (\S+)/i) {
	&areainfo($user, $1, $2)
# otherwise, unknown command;
    } else {
        print "# $user : $stuff\n";
        print EH ">$user Unknown command.\n";
    }
}

sub roadinfo
{
  my ($user, $wantall, $road) = @_;

  print "# $user asks for road $road\n";

  my $matches = &findByRoad($incidents{"road"}, $wantall, $road);

  my %shown = (), $count = 0;

  if (scalar(@$matches) == 0)
  {
    print EH ">$user No incidents found\n";
    print EH ">$user [Data last updated $lastdata]\n";
    return;
  }

  foreach $tm (@$matches)
  {
    if (!exists($shown{$tm->{road_traffic_message}->{message_id}}))
    {
      print EH ">$user ",$tm->{summary}->{content},"\n";
      $shown{$tm->{road_traffic_message}->{message_id}} = 1;
    }
    if ($count++ > 40)
    {
      print EH ">$user ** Too many matches **\n";
      last;
    }
  }
  print EH ">$user [Data last updated $lastdata]\n";
}

sub areainfo
{
  my ($user, $wantall, $area) = @_;

  print "# $user asks for area $area\n";

  my $matches = &findByArea($incidents{"road"}, $wantall, $area);

  my %shown = (), $count = 0;

  if (scalar(@$matches) == 0)
  {
    print EH ">$user No incidents found\n";
    print EH ">$user [Data last updated $lastdata]\n";
    return;
  }

  foreach $tm (@$matches)
  {
    if (!exists($shown{$tm->{road_traffic_message}->{message_id}}))
    {
      print EH ">$user ",$tm->{summary}->{content},"\n";
      $shown{$tm->{road_traffic_message}->{message_id}} = 1;
    }
    if ($count++ > 40)
    {
      print EH ">$user ** Too many matches **\n";
      last;
    }
  }
  print EH ">$user [Data last updated $lastdata]\n";
}

sub loopcheck {
    # check we're not looping
    $thistime = time;
    if ($thistime > $lasttime) {
        $lasttime = $thistime + 1;
        $thissec = 0;
    }
    $thissec++;
    if ($thissec > 30) {
        print "loop detected\n";
        print EH ".quit loop detect - quitting to avoid spamming\n";
        sleep 2;
        exit;
    }
}

sub loadXML
{
  print "Reading XML files...\n";
  opendir(XMLDIR, "/home/system/cps/travelnews/en/local/rtm");
  @xmlfiles = grep(!/^..?$/, readdir(XMLDIR));
  closedir(XMLDIR);

  $incidents{"road"} = [];

  foreach $xml (@xmlfiles)
  {
    next if ($xml !~ /xml$/i);

    open(X, "/home/system/cps/travelnews/en/local/rtm/$xml");
  
    print "# Loading $xml\n";
    $xmltext = "";
    while(<X>)
    {
      s/\&([^;]+);/$ent{$1}/g;
      s/\&/and/g;
      $xmltext .= $_;
    }
    close(X);
    $xmldata = XMLin($xmltext, ForceArray=> [ 'tpeg_message' ]);
  
    #print Dumper($xmldata);
    push @{$incidents{"road"}}, @{$xmldata->{tpeg_message}};

    $lastdata = $xmldata->{generation_time};
  }

}
  
sub findByRoad
{
  my ($all, $wantall, $road) = @_;

  my $matches = [];

  INC: foreach $incident (@$all)
  {
    next INC if (($incident->{road_traffic_message}->{severity_factor} eq 'very slight') && ($wantall !~ /all/));
    foreach $loc (@{$incident->{road_traffic_message}->{location_container}->{location_coordinates}->{location_descriptor}})
    {
      if ($loc->{descriptor_type} eq "road number")
      {
        my ($num,$name) = split(";",$loc->{descriptor},2);
        if (lc($num) eq lc($road) || lc($name) eq lc($road))
        {
          push(@$matches, $incident);
	  next INC;
        }
      }
    }
  }
  
  return $matches;
}

sub findByArea
{
  my ($all, $wantall, $area) = @_;

  my $matches = [];

  INC: foreach $incident (@$all)
  {
    next INC if (($incident->{road_traffic_message}->{severity_factor} eq 'very slight') && ($wantall !~ /all/));
    foreach $loc (@{$incident->{road_traffic_message}->{location_container}->{location_coordinates}->{location_descriptor}})
    {
      if (($loc->{descriptor_type} eq "county name" 
			|| $loc->{descriptor_type} eq "town name")
			&& ($loc->{descriptor} =~ /$area/i))
      {
        push(@$matches, $incident);
	next INC;
      }
    }
  }
  
  return $matches;
}

sub loadENT
{
  my ($file) = @_;

  open(ENT, $file);
  while(<ENT>)
  {
    if (/<\!ENTITY (\S+) "([^"]+)">/)
    {
      $ent{$1} = $2;
    }
  }
  close(ENT);
}
