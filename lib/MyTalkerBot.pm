package MyTalkerBot;
use base qw(Chatbot::TalkerBot);

use Exporter;
use vars qw(@EXPORT @EXPORT_OK);
@EXPORT = qw(connect_through_firewall connect_directly);
@EXPORT_OK = qw(TB_TRACE TB_LOG);

sub TB_LOG { Chatbot::TalkerBot::TB_TRACE(@_); }
sub TB_TRACE { Chatbot::TalkerBot::TB_TRACE(@_); }
sub connect_directly { Chatbot::TalkerBot::connect_directly(@_); }
sub connect_through_firewall { Chatbot::TalkerBot::connect_through_firewall(@_); }

sub listenLoop {
	my $self = shift;
	my $matchre = shift || die("You must supply a match string/regexp");
	my $callback = shift;
	my $interrupt = shift;
	
	# check that any supplied callback is a coderef 
	if ($callback && (ref( $callback ) ne 'CODE')) { die("The callback must be a code reference"); }
	if ($interrupt) { TB_LOG("Installing interrupt handler every $interrupt secs"); }
	
	my $STOPLOOP = 0;
	local $SIG{'ALRM'} = ($interrupt? sub { $callback->($self, 'ALRM'); alarm($interrupt); } : 'IGNORE');
	alarm($interrupt) if $interrupt;
	
	# enter event loop
	TB_LOG("Entering listening loop");
	my $socket = $self->{'connection'};
	while( <$socket> ) {

		# we don't know how long it will take to process this line, so stop interrupts
		alarm(0) if $interrupt;
		
		s/[\n\r]//g;
		TB_TRAFFIC( $_ );
		
		# only pay any attention to that regular expression
		if (($self->{'AnyCommands'} == 1) && (m/$matchre/)) {
			my $person = $1;
			my $text = $2;
			TB_LOG("attending: <$person> says <$text>");
			$self->{'lines_in'} += 1;
			my ($command, @args) = split(/ /, $text);

			# try to process the command internally, and then via the callback
			# Only allow TELLs to do internal commands
			if ( /^TELL\s+/ && $self->{'CommandHandler'}->isCommand( $command ) ) {
				$STOPLOOP = $self->{'CommandHandler'}->doCommand( $self, $person, $command, @args );
			} elsif ( $callback ) {
				$STOPLOOP = $callback->( $self, $person, $command, $_, @args );
			}
		}
		
		# command processing done, turn interrupts back on
		last if $STOPLOOP;
		alarm($interrupt) if $interrupt;
	}
	TB_LOG("Fallen out of listening loop");
}

1;

