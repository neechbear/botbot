#!/usr/bin/perl -w
# vim:ts=4:sw=4:tw=78

BEGIN {
	use File::Basename qw();
	use Cwd qw();
	use vars qw($ROOT);
	$ROOT = chdir(File::Basename::dirname($0)) && Cwd::getcwd();
}

use strict;
use Colloquy::Bot::Simple qw(daemonize);
use vars qw($VERSION $SELF $ROOT);

($SELF = $0) =~ s|^.*/||;
$VERSION = sprintf('%d.%02d', q$Revision: 1.2 $ =~ /(\d+)/g);
$SIG{'ALRM'} = sub { die "Alarm Caught; login took too long"; };
$SIG{'INT'}  = sub { die "Interrupt caught"; };

#rss_callback();
#die;

# Detach
daemonize("/tmp/$SELF.pid",1);

# Connect
alarm(10);
my $talker = Colloquy::Bot::Simple->new(
		host => '85.158.42.201',
		port => 1236,
		username => 'NewsBot',
		password => 'riugfreouvir',
	);
alarm(0);

# Loop
chdir($ROOT) || die "Unable to change directory to $ROOT: $!";
$talker->listenLoop(\&event_callback, 60);
$talker->quit;

exit;

sub event_callback {
	my $talker = shift;
	my $event = @_ % 2 ? { alarm => 1 } : { @_ };

	if (exists $event->{alarm}) {
		print "Callback called as ALARM interrupt handler\n";
		rss_callback($talker,$event);

	} elsif ($event->{msgtype} eq 'TELL') {
		$talker->whisper($event->{person}, 'Pardon?');
	}

	return 0;
}

sub rss_callback {
	my ($talker,$event) = @_;

	use DB_File;
	use LWP::Simple qw(mirror);
	use Date::Parse qw(str2time);
	use POSIX qw(tmpnam);
	use XML::RSS::LibXML qw();

	tie my %last, 'DB_File', '/var/tmp/newsbotHistory.dbm';
	my %feeds = (
	#		'http://newsrss.bbc.co.uk/rss/newsonline_uk_edition/latest_published_stories/rss.xml' => '%bbcnews',
			'http://newsrss.bbc.co.uk/rss/newsonline_uk_edition/technology/rss.xml' => '%technews',
			'http://www.infoworld.com/rss/news.xml' => '%technews',
	#		'http://rss.slashdot.org/Slashdot/slashdot' => '%technews',
			'http://www.theregister.co.uk/headlines.rss' => '%technews',
	#		'http://www.theinquirer.net/inquirer.rss' => '%technews',
		);

	while (my ($feed_uri,$destination) = each %feeds) {
		my $xmlfile = POSIX::tmpnam();
		mirror($feed_uri,$xmlfile) || next;

		my %recent = ( date => 0, title => '' );
		my $rss = XML::RSS::LibXML->new;
		eval { $rss->parsefile($xmlfile); };
		unlink $xmlfile;
		if ($@) {
			warn "Error while processing $feed_uri ($xmlfile): $@";
			next;
		}

		foreach my $item (@{$rss->{items}}) {
			my $date = str2time($item->{'dc:date'} || $item->{'pubDate'});
			next unless (defined $date && $date);
			if ($date > $recent{date}) {
				$recent{date} = $date;
				$recent{title} = $item->{title};
			}

			$last{$feed_uri} ||= "$recent{date}\t$recent{title}";
			next if ((split(/\t/,$last{$feed_uri}))[0] > $recent{date} ||
					 (split(/\t/,$last{$feed_uri}))[1] eq $recent{title});

			my $line = "$item->{title} - $item->{description} [".tinyURL($item->{link})."]\n";
			print $line;
			$talker->whisper($destination,$line);
		}

		$last{$feed_uri} = "$recent{date}\t$recent{title}";
	}
}

sub tinyURL {
	my $url = shift || undef;
	return undef unless defined $url;

	use LWP::UserAgent qw();
	my $ua = LWP::UserAgent->new(
			agent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) '.
					'Gecko/20050718 Firefox/1.0.4 (Debian package 1.0.4-2sarge1)',
			timeout => 10
		);

	my $shorturl = $url;
	unless ($shorturl =~ m#^https?://(tinyurl\.com|shrunk\.net)/[\w\d]+/?#i) {
		my $response = $ua->get("http://tinyurl.com/create.php?url=$url");
		return undef unless $response->is_success;
		if ($response->content =~ m|<input type=hidden name=tinyurl 
						value="(http://tinyurl.com/[a-zA-Z0-9]+)">|x) {
			$shorturl = $1;
		}
	}

	return $shorturl;
}



