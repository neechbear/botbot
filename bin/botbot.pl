#!/usr/bin/perl
# vim:ts=4:sw=4:tw=78

use strict;
use warnings;

BEGIN {
	use File::Basename qw();
	use Cwd qw();
	use vars qw($ROOT);
	$ROOT = chdir(File::Basename::dirname($0)) && Cwd::getcwd();
}

use lib ("$ROOT/lib");
use Socket;
use Getopt::Std qw();
use LWP::UserAgent qw();
use Finance::Currency::Convert::XE;
use XML::Simple qw();
use Net::Dict qw();
use File::Type qw();
use HTML::Strip qw();
use WWW::Search qw();
use Image::Info qw();
use HTML::Entities qw();
use Data::Dumper qw(Dumper);
use IMDB::Movie qw();
use Net::Whois::IANA qw();
use MyTalkerBot;

use vars qw($VERSION $SELF $ROOT $SEMA);

($SELF = $0) =~ s|^.*/||;
$VERSION = sprintf('%d.%02d', q$Revision: 1.28 $ =~ /(\d+)/g);
$SEMA = { 'last_who' => '' };

our $opts = { q => 0 };
Getopt::Std::getopts('dq',$opts);
daemonize("/tmp/$SELF.pid",$opts->{q}) if exists $opts->{d};
chdir($ROOT) || die "Unable to change directory to $ROOT: $!";




###########################################################
# Configuration

our $config = {
		server_host      => '85.158.42.201',
		server_port      => 1236,
		username         => 'BotBot',
		password         => 'riugfreouvir',
		loginsuccess     => 'End of MOTD',
		loginfail        => 'Incorrect login',
		usernameresponse => '<USER> <PASS>',
		usernameprompt   => 'HELLO colloquy',
		trigger          => '^(?:TELL|LISTTALK|TALK|OBSERVED \S+ (?:EMOTE @|TALK)) (\S{1,10})\s*[@%:>]?(.*)$',
		admin_password   => 'cuEuAS/hg0iFk',
		#admin_group      => ['neech', 'jen', 'heds'],
		commands         => {
			Say          => '',
			Tell         => '> ',
			Quit         => '.quit',
			Shout        => '! ',
			PEmoteList   => '<:>',
			EmoteList    => '<>',
			SayList      => '>>',
			Emote        => ': ',
			PEmote       => ':: ',
			REmote       => '< ',
			PREmote      => '<: ',
		}
	};

our $commands = {
		traceroute => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_traceroute,
			help => [
				'Syntax: traceroute <ip>',
				'Returns a traceroute from talker.tfb.net to <ip>'
			],
		},
		exchange => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_exchange,
			help => [
				'Syntax: exchange <value> <source currency> <target currency>',
				'Converts one currency to another. Value and source values are optional.',
			],
		},
		currencies => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_currencies,
			help => [
				'Syntax: currencies',
				'Displays a list of currencies available for use with the change command',
			],
		},
		dict => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_dict,
			help => [
				'Syntax: dict <word>',
				'Returns the dictionary definition of <word> from dict.org'
			],
		},
		ontv => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_ontv,
			help => [
				'Syntax: ontv <TV programme>',
				'Returns TV programmes within the next 6 days that match <TV programme>'
			],
		},
		remember => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_remember,
			help => [
				'Syntax: remember <something>',
				'Returns a URL previously logged by botbot relating to <something>'
			],
		},
		url => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_tinyurl,
		},
		imdbquote => {
			allow => [ qw(TELL) ],
			'sub' => \&_imdbquote,
			help => [
				'Syntax: imdbquote <IMDB ID>',
				'Will spam the crap out of you with IMDB movie quotes for <IMDB ID>'
			],
		},
		imdb => {
			allow => [ qw(OBVERVED TELL LISTTALK) ],
			'sub' => \&_imdb,
			help => [
				'Syntax: imdb <film title|IMDB ID>',
				'Return a list of movie titles matching <string> from imdb.com'
			],
		},
		iana => {
			allow => [ qw(TELL LISTTALK) ],
			'sub' => \&_iana,
			help => [
				'Syntax: iana <ip>',
				'Return IANA whois information for <ip>'
			],
		},
		googlefor => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_googlefor,
			help => [
				'Syntax: googlefor <string>',
				'Return the first match in Google for <string>'
			],
		},
		urban => {
			allow => [ qw(OBSERVED TELL LISTTALK) ],
			'sub' => \&_urbandictionary,
			help => [
				'Syntax: urban <term>',
				'Return the description of a term as defined on www.UrbanDictionary.com'
			],
		},
	};
$commands->{movie} = $commands->{imdb};
$commands->{moviequote} = $commands->{imdbquote};



###########################################################
# Connection and main loop

$Chatbot::TalkerBot::TRACING = 0;

alarm(10);
$SIG{'ALRM'} = sub { die("Alarm Caught - Login took too long"); };
$SIG{'INT'}  = sub { die("Interrupt Caught"); };

LOG("Connecting to $config->{server_host}:$config->{server_port}");
LOG("Using username <$config->{username}> and password <$config->{password}>");
our $socket = connect_directly($config->{server_host}, $config->{server_port});

my $talker = new MyTalkerBot($socket, {
		Username         => $config->{username},
		UsernameResponse => $config->{usernameresponse},
		UsernamePrompt   => $config->{usernameprompt},
		Password         => $config->{password},
		LoginSuccess     => $config->{loginsuccess},
		LoginFail        => $config->{loginfail}
	});

foreach my $command (keys %{$commands}) {
	$talker->installCommandHelp($command, $commands->{$command}->{'help'});
}

$talker->setTalkerCommands($config->{commands});
$talker->setAuthentication(
		$config->{admin_password},
		{ map { $_ => 1 } @{$config->{admin_group}} }
	);

alarm(0);
*MyTalkerBot::TB_TRAFFIC = \&raw_callback;
$talker->say('.observe Public');
$talker->listenLoop($config->{trigger}, \&event_callback, 5);

LOG("Closing down");
$talker->quit;

exit;




###########################################################
# Callback subroutines

sub event_callback {
	my ($talker, $person, $command, $raw, @args) = @_;

	# Never run a callback command for myself or another bot
	return 0 if $config->{username} eq $person;
	return 0 if $person =~ /Bot$/i;

	my @foo = @args; pop @foo;
	my $foo = "@foo"; my $bar = uc($foo);
	if ("$foo" eq "$bar" && @foo > 4) {
		LOG("'$foo' eq '$bar'");
		my $list = isList($raw);
		LOG("list = $list");
		if ($person =~ /zoe/i) {
			$talker->say(
					($list !~ /\@/ ? "<<$list" : '<@Public')." ".
					"comforts $person. there there, shhhhhh it'll be okay"
				);
		} else {
			$talker->say(
					($list !~ /\@/ ? ">>$list" : '>@Public')." ".
					"SHHHHHH!"
				);
		}
	} elsif ("@foo" =~ /\bpook/i && int(rand(3)) == 2) {
		my $list = isList($raw);
		$talker->say(
				($list !~ /\@/ ? ">>$list" : '>@Public')." ".
				"pook"
			);
	} elsif ( ( ($foo[0] =~ /mew|mews/i && @foo == 1) ||
				"@foo" =~ /mew(\s+mew)+/i ) && int(rand(3)) == 2) {
		my $list = isList($raw);
		if (int(rand(3)) == 2) {
			$talker->say(
					($list !~ /\@/ ? "<<$list" : '<@Public')." ".
					"purrs"
				);
		} else {
			$talker->say(
					($list !~ /\@/ ? ">>$list" : '>@Public')." ".
					"mew"
				);
		}
	}

	if ($person =~ /pkent/i) {
		if ($raw =~ /christian|religion|\bsan\b|\bvpn\b|\bnas\b|catholic/i) {
			$talker->say(".kick $person NO!");
		}
	}

	# Alarm callback every X seconds
	if ($person eq 'ALRM') {
		#LOG("Callback called as ALARM interrupt handler");
		if (!$SEMA->{last_who} || time() - $SEMA->{last_who} >= 60) {
			$talker->say('.who');
			$SEMA->{last_who} = time();
		}

	} else {
		my ($msgtype) = $raw =~ /^([A-Z]+)\s+/;

		# Interpret synchronous input as a command
		$command = 'url' if $raw =~ /\b((https?:\/\/|www\.)\S+)\b/i;

		if (ref($commands->{$command}->{'sub'}) eq 'CODE' &&
			grep(/^$msgtype$/,@{$commands->{$command}->{allow}})) {
			LOG("User '$person' has triggered the '$command' callback");
			return $commands->{$command}->{'sub'}( $talker,
							person => $person,
							command => $command,
							raw => $raw,
							args => [@args],
							list => isList($raw),
							msgtype => $msgtype,
						);

		} elsif ($msgtype eq 'TELL') {
			$talker->whisper($person, "Sorry, unrecognized command. Try 'help'");
			return 0;
		}
	}

	return 0;
}

sub raw_callback {
	LOG('[',@_,']');
	local $_ = $_[0];
	chomp;

	if (/^LISTINVITE\s+.+\s+To respond, type (.+)$/) {
		$talker->say($1);
	}

	if (/$config->{trigger}/) {
		my ($person,$str) = ($1,$2);

		# Never run a callback command for myself or another bot
		return 0 if $config->{username} eq $person;
		return 0 if $person =~ /Bot$/i;

		my $list = isList($_);
		$str =~ s/\{.+?\}\s*$//;
		$str =~ s/^\s+|\s+$//g;

#		if (lc($person) eq 'tims' && $str =~ /^\s*t\s*m\s*i/i) {
#			$talker->shout('TIMMAH!');
#		}

		# Basic calculator functionality
		if ($str =~ /^[\s=0-9pi]+$/i && lc($str) ne 'pi') { # Just a number
		} elsif ($str =~ /^(\s*(?:hex|oct|dec|bin)\s+of\s+)?([pi\=\;\(\)\s\d\+\-\/\*\^\%]+)$/i) {
			my $convert = $1 || 'dec';
			warn "convert = $convert";

			my $calc = $2;
			$calc =~ s/pi/\(104348\/33215\)/gi;
			my $changed_calc = 0;
			if ($calc =~ s/[pi]//gi) {
				$changed_calc++;
			}
			warn "calc = $calc";

			my $result = eval "($calc)+1-1";
			warn "result = $result";

			# Convert the result to another base if necessary
			if ($result =~ /^[0-9\.]+$/) {
				my $Xresult = $result;
				if ($convert =~ /\s*hex of\s*/i) {
					$Xresult = sprintf("%X", $result);

				} elsif ($convert =~ /\s*oct of\s*/i) {
					$Xresult = sprintf("%o", $result);

				} elsif ($convert =~ /\s*bin of\s*/i) {
					$Xresult = unpack("B*", pack("N", $result));
				}
				$result = $Xresult;
				warn "result = $result";
				warn "Xresult = $Xresult";
			}

			if (!$@ && length($result)) {
				$talker->whisper(
						($list ? $list : $person),
						"I didn't like your statement, so I changed it to $convert $calc"
					) if $changed_calc;
				$talker->whisper(
						($list ? $list : $person),
						"$str = $result"
					);
			}
		}
	}

	if (my ($line) = $_ =~ /^WHO(?:HDR)?\s+(.+)$/) {
		my $mode = /Users on .+ at the moment/ ? '>' : '>>';
		my $file = "$ROOT/logs/who.log";
		if (open(FH, "$mode$file")) {
			print FH "$line\n";
			close(FH);
		} else {
			warn "Unable to open file handle FH for file '$file': $!";
		}
	}
}




###########################################################
# Command subroutines

sub _currencies {
	my $talker = shift;
	my $event = { @_ };

	my $obj = Finance::Currency::Convert::XE->new()       
				|| die "Failed to create object\n" ;
	my @currencies = $obj->currencies;

	my $c = 0;
	my @lines;
	my $line;
	for (@currencies) {
		$c++;
		$c = 0 unless ($c % 10);
		$line .= "$_   ";
		if ($c == 0) {
			push(@lines,$line);
			$line = '';
		}
	}
	push(@lines,$line) unless $c == 0;

	$talker->whisper(
			($event->{list} ? $event->{list} : $event->{person}),
			$_
		) for @lines;
	return 0;
}

sub _exchange {
	my $talker = shift;
	my $event = { @_ };
	my @arg = @{$event->{args}};

	my $obj = Finance::Currency::Convert::XE->new()       
				|| die "Failed to create object\n" ;

	my $gaveValue = 0;
	my $value = 1;
	if ($arg[0] && $arg[0] =~ /([\d\.]+)/) {
		$value = $1;
		$gaveValue = 1;
		shift @arg;
	}

	my $gaveSource = 0;
	my $source = 'GBP';
	if ($arg[0] && $arg[0] =~ /^([A-Z]{3})$/i) {
		$source = uc($1);
		$gaveSource = 1;
		shift @arg;
	}

	my $target = 'GBP';
	if ($arg[0] && $arg[0] =~ /^([A-Z]{3})$/i) {
		$target = uc($1);
		shift @arg;
	} else {
		unless ($gaveValue && $gaveSource) {
			$target = $source;
			$source = 'GBP';
		}
	}

	my $result = $obj->convert(
				'source' => $source,
				'target' => $target,
				'value' => $value,
				'format' => 'text'
		) || warn "Could not convert: ".$obj->error()."\n";

	if ($result) {
		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				"$value $source is $result $target\n"
			);
	} else {
		$talker->whisper(
				$event->{person},
				"I failed to convert $value $source in to $target; sorry\n"
			);
	}

	return 0;
}


sub _traceroute {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);
	pop @{$event->{args}} if $event->{list};
	my $ip = isIP($event->{args}->[0]) ? $event->{args}->[0] :
				(host2ip($event->{args}->[0]))[0];

	unless (isIP($ip)) {
		$talker->whisper(
				$event->{person},
				"Sorry; $event->{args}->[0] isn't a valid host/IP"
			);
		return 0;
	}

	if (open(TR,"/usr/sbin/traceroute -w 3 -m 20 $ip|")) {
		my $failCnt = 0;
		while (local $_ = <TR>) {
			chomp;
			$failCnt++ if /\* \* \*/;
			last if $failCnt >= 3;
			$talker->whisper(
					($event->{list} ? $event->{list} : $event->{person}),
					$_
				);
		}
		close(TR);
	}

	return 0;
}

sub _remember {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);
	pop @{$event->{args}} if $event->{list};
	my $str = join(' ',@{$event->{args}});
	$str =~ s/\s+/\.\*/g;

	my @reply;
	if (open(URL,"<$ROOT/logs/url.log")) {
		while (local $_ = <URL>) {
			chomp;
			if (/$str/i) {
				my ($time,$person,$url,$tinyurl,$list,$title) = split(/\t/,$_);
				unless ($title) {
					my ($title2,$response) = getHtmlTitle($url);
					$title = $title2;
				}
				unless ($tinyurl) {
					$tinyurl = tinyURL($url) || $url;
				}
				push @reply, "$person once mentioned $tinyurl - $title";
			}
		}
		close(URL);
	}

	@reply = ("Sorry. I don't remember $str.") unless @reply;

	$talker->whisper(
			($event->{list} ? $event->{list} : $event->{person}),
			$reply[int(rand(@reply))]
		);

	return 0;
}

sub _dict {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);
	pop @{$event->{args}} if $event->{list};
	my $str = join(' ',@{$event->{args}});

	my @reply;
	my $dict = Net::Dict->new('dict.org');
	my $h = $dict->define($str);
	foreach my $i (@{$h}) {
		my ($db, $def) = @{$i};
		my @lines = split(/\n/,$def);
		my $c = 0;
		my $maxlines = 7;
		my $skipped = 1;
		for (@lines) {
			if ($c >= $maxlines && $event->{msgtype} ne 'TELL') {
				push @reply, " ... (truncated; displayed $maxlines lines of ".@lines.") ...";
				last;
			}
			push @reply,$_;
			$c++;
		}
		last;
	}

	unless (@reply) {
		$talker->whisper(
				$event->{person},
				'Sorry, I couldn\'t find a dictionary definition for you'
			);
	} else {
		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$_
			) for @reply;
	}

	return 0;
}

sub _ontv {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);
	pop @{$event->{args}} if $event->{list};
	my $str = join(' ',@{$event->{args}});

	my $xs = new XML::Simple();
	my $listings = $xs->XMLin("$ROOT/data/blebtv/data.xml",
						ForceArray => 1, KeyAttr => 'key');

	my %channels;
	for my $c (@{$listings->{channel}}) {
		$channels{$c->{id}} = $c->{'display-name'}->[0];
	}

	my $today = isodate(time);
	my $tomorrow = isodate(time + (60*60*24));

	my @reply;
	for my $p (@{$listings->{programme}}) {
		# Skip regional channels
		next if $p->{channel} =~ /_(ireland|scotland|wales)$/;

		# Only search today and tomorrow
		next if $p->{start} !~ /^($today|$tomorrow)/;

		if ($p->{title}->[0]->{content} =~ /$str/i) {
			my $prog = {
					title => $p->{title}->[0]->{content},
					desc => $p->{desc}->[0]->{content},
					start => isodate2prettydate($p->{start}),
					end => isodate2prettydate($p->{stop}),
					channel => $channels{$p->{channel}},
				};
			push @reply, sprintf('%s on %s:  %s  --  %s',
							$prog->{start},
#							$prog->{end},
							$prog->{channel},
							$prog->{title},
							$prog->{desc}
						);
		}
	}

	@reply = sort @reply;

	unless (@reply) {
		$talker->whisper(
				$event->{person},
				'Sorry, I couldn\'t find any matching TV programmes for you, showing today or tomorrow'
			);
	} elsif (($#reply + 1) > 10) {
		my $matches = $#reply + 1;
		$talker->whisper(
				$event->{person},
				"Sorry, searching for the programme '$str' returned more than 10 matches (found $matches matches)"
			);
	} else {
		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$_
			) for @reply;
	}

	return 0;
}

sub _iana {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]) && isIP($event->{args}->[0]);
	my $ip = $event->{args}->[0];

	eval {
		my $iana = new Net::Whois::IANA;
		$iana->whois_query(-ip=>$ip);

		my @reply = ("IANA Details for $ip:");
		push @reply, "  Country: " . $iana->country();
		push @reply, "  Netname: " . $iana->netname();
		push @reply, "  Descr: "   . $iana->descr();
		push @reply, "  Status: "  . $iana->status();
		push @reply, "  Source: "  . $iana->source();
		push @reply, "  Server: "  . $iana->server();
		push @reply, "  Inetnum: " . $iana->inetnum();

		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$_
			) for @reply;
	};

	return 0;
}

sub _googlefor {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);
	pop @{$event->{args}} if $event->{list};

	my $key = 'xs9uhr9QFHJsxYJV6zO5TBob4K7kuygs';
	my $search = WWW::Search->new('Google', key => $key, safe => 0);
	$search->native_query(join(' ',@{$event->{args}}));
	my $result = $search->next_result();

	if (defined $result) {
		my $hs = HTML::Strip->new();
		my $reply = $hs->parse(' '.$result->url.' - '.
							$result->title.' - '.
							$result->description);

		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$reply
			);
	} else {
		$talker->whisper(
				$event->{person},
				'Sorry. I failed miserably to look that up for you'
			);
	}

	return 0;
}

sub _urbandictionary {
	my $talker = shift;
	my $event = { @_ };

	return 0 unless length($event->{args}->[0]);

	my $key = 'e1022d9e0af608374a5c88f5e0f379c5';
	my $search = WWW::Search->new('UrbanDictionary', key => $key);
	$search->timeout(5);
	pop @{$event->{args}} if $event->{list};
	$search->native_query(join(' ', @{$event->{args}}));

	my @results = $search->results();
	unless (exists $results[0]->{description} && length($results[0]->{description})) {
		$talker->whisper(
				$event->{person},
				'Sorry. I failed miserably to look that up for you'
			);

	} else {
		my $reply = sprintf("'%s': %s %s",
				$results[0]->{word},
				$results[0]->{description},
				($results[0]->{example} ? "(Example: $results[0]->{example})" : '')
			);
		$reply = sprintf("Result 1 of %d for %s", ($#results + 1), $reply) if ($#results + 1) > 1;

		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$reply
			);
	}

	return 0;
}

sub _imdbquote {
	my $talker = shift;
	my $event = { @_ };

	# Create an LWP object to work with
	my $ua = LWP::UserAgent->new(
			agent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050718 Firefox/1.0.4 (Debian package 1.0.4-2sarge1)',
			timeout => 10
		);

	# Get the IMDB ID reference
	my $id;
	if (defined $event->{args}->[0] && $event->{args}->[0] =~ /^\d{7}$/) {
		$id = $event->{args}->[0];
	} else {
		pop @{$event->{args}} if $event->{list};
		my ($popular,@matches) = searchIMDB(join(' ', @{$event->{args}}));
		warn $_ for @matches;
		if (@matches && $matches[0] =~ /\s*(\d{7})\s*/) {
			$id = $1;
			warn $id;
		}
	}

	# Lookup a specific IMDB ID reference
	if ($id =~ /^\d{7}$/) {
		my $response = $ua->get("http://www.imdb.com/title/tt$id/quotes");
		my $html = '';
		if ($response->is_success) {
			$html = $response->content;
		} else {
			$talker->whisper(
					$event->{person},
					'Sorry, IMDB did not return a valid page; '.$response->status_line
				);
			return 0;
		}

		unless ($html =~ /Memorable Quotes from/ && $html =~ /<a name="qt\d+">/) {
			$talker->whisper(
					$event->{person},
					'Sorry, IMDB did not return any quotes for that movie'
				);
			return 0;
		}

		$html =~ s/.*Memorable Quotes from .+?(\n|\cM)//gs;
		$html =~ s/<br>\s*<br>\s*<div\s*.*//gs;
		$html =~ s/<hr.+?>/---<br>/gs;
		$html =~ s/(\n|\cM)//gs;
		$html =~ s/<br>/\n/gs;

		my $hs = HTML::Strip->new();
		my @reply = split(/\n/,$hs->parse($html));
		$hs->eof;

		$talker->whisper(
				$event->{person},
				$_
			) for @reply;
	}

	return 0;
}

sub _imdb {
	my $talker = shift;
	my $event = { @_ };

	# Lookup a specific IMDB ID reference
	if (defined $event->{args}->[0] && $event->{args}->[0] =~ /^\d{7}$/) {
		my $id = $event->{args}->[0];
		my $movie = IMDB::Movie->new($id);

		my @reply;
		push @reply, sprintf('%s - %s (%s)',
						$id,
						$movie->title,
						$movie->year
					);

		push @reply, sprintf('  Director%s: %s',
						(@{$movie->director} == 1 ? '' : 's'),
						join(' / ',@{$movie->director})
					) if @{$movie->director};
		push @reply, sprintf('  Writer%s: %s',
						(@{$movie->writer} == 1 ? '' : 's'),
						join(' / ',@{$movie->writer})
					) if @{$movie->writer};
		push @reply, sprintf('  Genre%s: %s',
						(@{$movie->genres} == 1 ? '' : 's'),
						join(' / ',@{$movie->genres})
					) if @{$movie->genres};

		my $detailurl = tinyURL("http://www.imdb.com/title/tt$id/");
		push @reply, sprintf('  Details: %s',
						$detailurl
					) if defined $detailurl;

		my $quotesurl = tinyURL("http://www.imdb.com/title/tt$id/quotes");
		push @reply, sprintf('  Quotes: %s',
						$quotesurl
					) if defined $quotesurl;

		$talker->whisper(
				($event->{list} ? $event->{list} : $event->{person}),
				$_
			) for @reply;

	# Search for titles
	} else {
		pop @{$event->{args}} if $event->{list};
		my ($recLimit,@matches) = searchIMDB(join(' ', @{$event->{args}}));
		$recLimit = 3 if $recLimit < 3;

		unless (@matches) {
			$talker->whisper(
					$event->{person},
					'Sorry, I failed to return an IMDB match for your query'
				);
		} else {
			unshift @matches, 'Showing '.(($#matches + 1) < $recLimit ?
					($#matches + 1) : $recLimit).' results out of '.($#matches + 1);
			for (my $i = 0; $i <= $recLimit; $i++) {
				$talker->whisper(
						($event->{list} ? $event->{list} : $event->{person}),
						$matches[$i]
					);
			}
		}
	}

	return 0;
}

sub _tinyurl {
	my $talker = shift;
	my $event = { @_ };

	# Extract the URL from what they said
	my $url = '';
	if ($event->{raw} =~ /\b((https?:\/\/|www\.)\S+)\b/i) {
		$url = $1;
	}
	$url = "http://$url" unless $url =~ /^https?:\/\//i;

	# Check that the URL at least has a valid hostname or IP address
	if ($url =~ /https?:\/\/(?:\w+?:\w+?@)?([a-zA-Z0-9-\.]+)(:\d+)?/) {
		my $str = $1;
		if (!isIP($str) && host2ip($str) eq $str) {
			if ($event->{msgtype} eq 'TELL') {
				$talker->whisper(
						$event->{person},
						"I don't think $str is a valid hostname within that URL."
					);
			}
			return 0;
		}
	}

	# Go and get the URL they spoke about
	my ($title,$response) = getHtmlTitle($url);
	if (!$title) {
		$title = "[".$response->status_line."]";
		$talker->whisper(
				$event->{person},
				'That URL does not return a valid webpage; '.$response->status_line
			);
	}

	# Go and get the TinyURL
	my $shorturl = tinyURL($url) || $url;

	$talker->whisper(
			$event->{person},
			'Sorry, I failed to convert that to a TinyURL'
		) unless defined $shorturl;

	# Respond
	my $reply = " $shorturl - $title";
	$talker->whisper(
			($event->{list} ? $event->{list} : $event->{person}),
			$reply
		);

	# Write the URL to our log
	if (open(FH, ">>$ROOT/logs/url.log")) {
		$title =~ s/\s+/ /g;
		$title = '' if $title eq '[No title information available]';
		$shorturl = '' if $shorturl eq $url;
		print FH sprintf("%d\t%s\t%s\t%s\t%s\t%s\n",
			time(), $event->{person}, $url, $shorturl, $event->{list}, $title);
		close(FH);
	} else {
		warn "Unable to open file handle FH for file '$ROOT/logs/url.log': $!";
	}

	return 0;
}








###########################################################
# Utility subroutines

sub LOG {
	if (open(LOG, ">>$ROOT/logs/botbot.log")) {
		my @x = @_;
		chomp for @x;
		my $line = sprintf("[%s] %s\n", scalar(localtime(time())), join('', @x));
		print LOG $line;
		print $line;
		close(LOG);
	} else {
		warn "Unable to open file handle LOG for file '$ROOT/logs/botbot.log': $!";
	}
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
		($title) = $content =~ /<title>(.*?)<\/title>/si;
		if ($title) {
			my $hs = HTML::Strip->new();
			$title = $hs->parse($title);
			$title = HTML::Entities::decode($title);
			$title =~ s/\n/ /gs; $title =~ s/\s\s+/ /g;
		}
		if (!$title) {
			eval {
				my $info = Image::Info::image_info(\$content);
				my($w, $h) = Image::Info::dim($info);
				if ($w && $h) {
					$title = "$info->{file_media_type} ${w}x${h}";
					if (exists $info->{BitsPerSample}->[0]) {
						$title .= " (".sum(@{$info->{BitsPerSample}})." bit)";
					}
				}
			};
			if ($@ || !$title) {
				eval {
					my $ft = File::Type->new();
					$title = $ft->checktype_contents($content);
				};
			}
		}
	} else {
		return ('',$response);
	}

	sub sum {
		my $x = 0;
		for (@_) { $x += $_; };
		return $x;
	}

	$title = '[No title information available]'
		if !defined $title || $title =~ /^\s*$/;

	return ($title,$response);
}

sub searchIMDB {
	my $title = shift || undef;
	return undef unless defined $title;
	$title =~ s/\s+/%20/;
	my $url = sprintf('http://www.imdb.com/find?q=%s;s=tt', $title);

	# Create an LWP object to work with
	my $ua = LWP::UserAgent->new(
			agent => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.7.8) Gecko/20050718 Firefox/1.0.4 (Debian package 1.0.4-2sarge1)',
			timeout => 10
		);

	my @matches;
	my $popular = 0;
	my $response = $ua->get($url);
	if ($response->is_success) {
		for (split(/\n+/, $response->content)) {
			if ($_ =~ m#Popular Titles</b> \(Displaying (\d+) Results\)#) {
				$popular = $1;
			}
			if (m#href="/title/tt(\d+)/".*?>(.+?)</a>(.+?)</li>#) {
				my ($id,$title,$extra) = ($1,$2,$3);
				my ($year,$type) = ('','');
				($year) = $extra =~ m/\((\d{4})\)/;
				($type) = $extra =~ m/\(([A-Za-z]+)\)/;
				my $reply = "  $id - ".HTML::Entities::decode_entities($title);
				$reply .= " ($year)" if $year;
				$reply .= " ($type)" if $type;
				push @matches, $reply;
			}
		}
		return ($popular,@matches);
	}

	return undef;
}

sub isodate {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift || time);
	$year += 1900;
	$mon++;
	return sprintf('%04d%02d%02d',$year,$mon,$mday);
}

sub isodate2prettydate {
	local $_ = shift || '';
	return $_ unless /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/;
	return "$1/$2/$3 $4:$5";
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

sub isList {
	local $_ = shift || '';
	if (/^LISTTALK\s+.+\{(\w+?)\}/) {
		return '%'.$1;
	} elsif (/^OBSERVED\s+(\S+)\s+/) {
		return '@'.$1;
	}
	return undef;
}

# Daemonize self
sub daemonize {
	# Pass in the PID filename to use
	my $pidfile = shift || undef;

	# Boolean true will supress "already running" messages if you want to
	# spawn a process out of cron every so often to ensure it's always
	# running, and to respawn it if it's died
	my $cron = shift || 0;

	# Set the fname to the filename minus path
	(my $SELF = $0) =~ s|.*/||;
	$0 = $SELF;

	# Lazy people have to have everything done for them!
	$pidfile = "/tmp/$SELF.pid" unless defined $pidfile;

	# Check that we're not already running, and quit if we are
	if (-f $pidfile) {
		unless (open(PID,$pidfile)) {
			warn "Unable to open file handle PID for file '$pidfile': $!\n";
			exit 1;
		}
		my $pid = <PID>; chomp $pid;
		close(PID) || warn "Unable to close file handle PID for file '$pidfile': $!\n";

		# This is a good method to check the process is still running for Linux
		# kernels since it checks that the fname of the process is the same as
		# the current process
		if (-f "/proc/$pid/stat") {
			open(FH,"/proc/$pid/stat") || warn "Unable to open file handle FH for file '/proc/$pid/stat': $!\n";
			my $line = <FH>;
			close(FH) || warn "Unable to close file handle FH for file '/proc/$pid/stat': $!\n";
			if ($line =~ /\d+[^(]*\((.*)\)\s*/) {
				my $process = $1;
				if ($process =~ /^$SELF$/) {
					warn "$SELF already running at PID $pid; exiting.\n" unless $cron;
					exit 0;
				}
			}

		# This will work on other UNIX flavors but doesn't gaurentee that the
		# PID you've just checked is the same process fname as reported in you
		# PID file
		} elsif (kill(0,$pid)) {
			warn "$SELF already running at PID $pid; exiting.\n" unless $cron;
			exit 0;

		# Otherwise the PID file is old and stale and it should be removed
		} else {
			warn "Removing stale PID file.\n";
			unlink($pidfile) || warn "Unable to unlink PID file '$pidfile': $!\n";
		}
	}

	# Daemon parent about to spawn
	if (my $pid = fork) {
		warn "Forking background daemon, process $pid.\n";
		exit 0;

	# Child daemon process that was spawned
	} else {
		# Fork a second time to get rid of any attached terminals
		if (my $pid = fork) {
			warn "Forking second background daemon, process $pid.\n";
			exit 0;
		} else {
			unless (defined $pid) {
				warn "Cannot fork: $!\n";
				exit 2;
			}
			unless (open(FH,">$pidfile")) {
				warn "Unable to open file handle FH for file '$pidfile': $!\n";
				exit 3;
			}
			print FH $$;
			close(FH) || warn "Unable to close file handle FH for file '$pidfile': $!\n";

			# Sort out file handles and current working directory
			chdir '/' || warn "Unable to change directory to '/': $!\n";
			close(STDOUT) || warn "Unable to close file handle STDOUT: $!\n";
			close(STDERR) || warn "Unable to close file handle STDERR: $!\n";
			open(STDOUT,'>>/dev/null'); open(STDERR,'>>/dev/null');

			return $$;
		}
	}
}


