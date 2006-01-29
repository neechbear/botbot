#!/usr/bin/perl
# vim:ts=4:sw=4:tw=78

use strict;
use warnings;

use LWP::UserAgent qw();
use HTML::Strip qw();
use Image::Info qw();
use HTML::Entities qw();


if (open(IN,"<url.log") && open(OUT,">newurl.log")) {
	while (local $_ = <IN>) {
		chomp;
		my ($time,$person,$url,$tinyurl,$list,$title) = split(/\t/,$_);
		if ($title && $tinyurl) {
			print OUT "$_\n";
		} else {
			$tinyurl = tinyURL($url) unless $tinyurl;
			unless ($title) {
				my ($title2,$response) = getHtmlTitle($url);
				$title = $title2;
			}
			printf OUT ("%s\t%s\t%s\t%s\t%s\t%s\n",
					$time,$person,$url,$tinyurl,$list,$title
				);
		}
	}
	close(OUT);
	close(IN);
}

sub getHtmlTitle {
	my $url = shift || undef;
	return '[No title information available]' unless defined $url;

	# Create an LWP object to work with
	my $ua = LWP::UserAgent->new(
			agent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050718 Firefox/1.0.4 (Debian package 1.0.4-2sarge1)',
			max_size => 102400,
			timeout => 10
		);

	# Go and get the URL they spoke about
	my $response = $ua->get($url);
	my $title = '';
	if ($response->is_success) {
		my $content = $response->content();
		($title) = $content =~ /<title>(.*)<\/title>/si;
		if ($title) {
			
			$title = HTML::Entities::decode($title);
			$title =~ s/\n/ /gs; $title =~ s/\s\s+/ /g;
		} else {
			eval {
				my $info = Image::Info::image_info(\$content);
				my($w, $h) = Image::Info::dim($info);
				if ($w && $h) {
					$title = "$info->{file_media_type} ${w}x${h}";
					if (exists $info->{BitsPerSample}->[0]) {
						$title .= " ($info->{BitsPerSample}->[0] bit)";
					}
				}
			}
		}
	} else {
		return ('',$response);
	}

	$title = '[No title information available]'
		if !defined $title || $title =~ /^\s*$/;

	return ($title,$response);
}

sub tinyURL {
	my $url = shift || undef;
	return undef unless defined $url;

	my $ua = LWP::UserAgent->new(
			agent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050718 Firefox/1.0.4 (Debian package 1.0.4-2sarge1)',
			timeout => 10
		);

	my $shorturl = $url;
	unless ($shorturl =~ m#^https?://(tinyurl\.com|shrunk\.net)/[\w\d]+/?#i) {
		my $response = $ua->get("http://tinyurl.com/create.php?url=$url");
		return undef unless $response->is_success;
		if ($response->content =~ m|<input type=hidden name=tinyurl value="(http://tinyurl.com/[a-zA-Z0-9]+)">|) {
			$shorturl = $1;
		}
	}

	return $shorturl;
}

sub ip2host {
	my $ip = shift;
	my @numbers = split(/\./, $ip);
	my $ip_number = pack("C4", @numbers);
	my ($host) = (gethostbyaddr($ip_number, 2))[0];
	if (defined $host && $host) {
		return $host;
	} else {
		return $ip;
	}
}

sub isIP {
	return 1 if $_[0] =~ /\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
							(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
							(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.
							(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/x;
	return 0;
}

sub resolve {
	return ip2host(@_) if isIP($_[0]);
	return host2ip(@_);
}

sub host2ip {
	my $host = shift;
	my @addresses = gethostbyname($host);
	if (@addresses > 0) {
		@addresses = map { inet_ntoa($_) } @addresses[4 .. $#addresses];
		return @addresses;
	} else {
		return $host;
	}
}

