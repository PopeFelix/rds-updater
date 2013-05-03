use strict;
use warnings;

package Radio::RDS::Inovonics730;
use IO::Socket::INET;
use Carp qw/carp croak/;
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Params::Validate;
use Class::MOP::Class;
use Readonly;
use Net::IP;
use English qw/-no_match_vars/;
use Carp::Assert;
use feature qw/say switch/;

# note: Net::Cmd will not work with the Inovonics 730 because the interface does not implement a command based protocol as in SMTP / FTP (principally, 
# the interface does not return 2xx, 3xx, 4xx, 5xx status codes) 

Readonly my $DPSS_MAX => 9;
Readonly my $DPS_MAX_LENGTH => 128;
Readonly my $TIMER_MAX => 255;
Readonly my $PARSE_MAX => 9;
Readonly my $RT_MAX => 64;
Readonly my $DRTS_MAX => 9;
Readonly my $IPv4 => 4;
Readonly my $IPv6 => 6;
Readonly my $PORT_MAX => 65535;
Readonly my $PTY_MAX => 31;
Readonly my $DYNDNS_MAX => 4;
Readonly my $PTYN_MAX_LENGTH => 8;
Readonly my $DYNDNS_HOSTNAME_MAX_LENGTH => 26;
Readonly my $DYNDNS_USERNAME_MAX_LENGTH => 26;
Readonly my $DYNDNS_PASSWORD_MAX_LENGTH => 21;
Readonly my $UTC_MIN_OFFSET => -12.0;
Readonly my $UTC_MAX_OFFSET => 12.0;
Readonly my $CT_MAX => 2;
Readonly my $ECHO_MAX => 2;
Readonly my $SITE_MAX => 1023;
Readonly my $ENCODER_MAX => 63;
Readonly my $RTPRUN_MAX => 2;
Readonly my $RTPTOG_MAX => 3;
Readonly my $NETPASS_MAX => 16;
Readonly my $DELAY_MAX => 120;
Readonly my $RDSLEVEL_MAX => 3.0;

Readonly my $SUPPORTED_COMMANDS => {
    q/DPS/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] <= $DPS_MAX_LENGTH; },
    },
    q/DPSDEFAULT/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] <= $DPS_MAX_LENGTH; },
    },
    q/DPSTIMER/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $TIMER_MAX; },
    },
    q/DPSS/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $DPSS_MAX; },
    },
    q/PARSE/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $PARSE_MAX; },
    },
    q/TEXT/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] >= 0 && length $_[0] <= $RT_MAX; },
    },
    q/RTDEFAULT/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] >= 0 && length $_[0] <= $RT_MAX; },
    },
    q/RTTIMER/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $TIMER_MAX; },
    },
    q/DRTS/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $DRTS_MAX; },
    },
    q/PI/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^[A-F0-9]{4}$/ixsm; },
    },
    q/CALL/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^[W,K][A-Z]{3}/ixsm; },
    },
    q/PTY/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $PTY_MAX; },
    },
    q/PTYN/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] >= 0 && length $_[0] <= $PTYN_MAX_LENGTH; },
    },
    q/MS/ => {
        'isa' => 'Bool',
    },
    q/DI/ => {
        'isa' => 'Bool',
    },
    q/TP/ => {
        'isa' => 'Bool',
    },
    q/TA/ => {
        'isa' => 'Bool',
    },
    q/TATIME/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $TIMER_MAX; },
    },
    q/DHCP/ => {
        'isa' => 'Bool',
    },
    q/IP/ => {
        'isa' => 'Str',
        'validate' => sub { return Net::IP::ip_is_ipv4($_[0]); },
    },
    q/GATEWAY/ => {
        'isa' => 'Str',
        'validate' => sub { return Net::IP::ip_is_ipv4($_[0]); },
    },
    q/DNS/ => {
        'isa' => 'Str',
        'validate' => sub { return Net::IP::ip_is_ipv4($_[0]); },
    },
    q/SUBNET/ => {
        'isa' => 'Str',
        'validate' => sub {
            my $mask = $_[0];
            my $binmask = Net::IP::ip_iptobin($mask, $IPv4);
            return Net::IP::ip_is_valid_mask($binmask, $IPv4);
         },
    },
    q/PORT1/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $PORT_MAX; },
    },
    q/PORT2/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $PORT_MAX; },
    },
    q/PORT3/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $PORT_MAX; },
    },
    q/DYNDNS/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $DYNDNS_MAX; },
    },
    q/DYNDNSHOST/ => {
        'isa' => 'Str',
        'validate' => sub { return length($_[0]) <= $DYNDNS_HOSTNAME_MAX_LENGTH; },
    },
    q/DYNDNSUSER/ => {
        'isa' => 'Str',
        'validate' => sub { return length($_[0]) <= $DYNDNS_USERNAME_MAX_LENGTH; },
    },
    q/DYNDNSPASS/ => {
        'isa' => 'Str',
        'validate' => sub { return length($_[0]) <= $DYNDNS_PASSWORD_MAX_LENGTH; },
    },
    q/TIME/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^(0{0,1}[0-9]|1[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$/xsm; },
    },
    q/DATE/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^(0[0-9]|1[0-2])\/([0-2][0-9]|3[0-1])\/\d{2}/xsm; }
    },
    q/UTC/ => {
        'isa' => 'Float',
        'validate' => sub { return $_[0] >= $UTC_MIN_OFFSET && $_[0] <= $UTC_MAX_OFFSET; },
    },
    q/DST/ => {
        'isa' => 'Bool',
    },
    q/CT/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $CT_MAX; },
    },
    q/ECHO/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $ECHO_MAX; },
    },
    q/RDS/ => {
        'isa' => 'Bool',
    },
    q/UECP/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^[0-9A-F]$/ixsm; },
    },
    q/SITE/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $SITE_MAX; },
    },
    q/ENCODER/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $ENCODER_MAX; },
    },
    q/HEADER/ => {
        'isa' => 'Bool',
    },
    q/SPEED/ => {
        'isa' => 'Int',
        'validate' => sub { 
            return $_[0] == 1200 || $_[0] == 2400 || $_[0] == 4800 || $_[0] == 9600;
        },
    },
    q/RTP/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^\d{2},\d{2},\d{2},\d{2},\d{2},\d{2}$/; },
    },
    q/RTPDEFAULT/ => {
        'isa' => 'Str',
        'validate' => sub { return $_[0] =~ m/^\d{2},\d{2},\d{2},\d{2},\d{2},\d{2}$/; },
    },
#    q/RTPCFG/ => { # documented as "for future use"
#    },
    q/RTPRUN/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $RTPRUN_MAX; },
    },
    q/RTPTOG/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $RTPTOG_MAX; },
    },
    q/SCHEDULE/ => {
        'isa' => 'Bool',
    },
    q/NETPASS/ => {
        'isa' => 'Str',
        'validate' => sub { return length $_[0] <= $NETPASS_MAX; },
    },
    q/DELAY/ => {
        'isa' => 'Int',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $DELAY_MAX; },
    },
    q/ODA1/ => {
        'isa' => 'Str',
    },
    q/ODA2/ => {
        'isa' => 'Str',
    },
    q/RDSLEVEL/ => {
        'isa' => 'Float',
        'validate' => sub { return $_[0] >= 0 && $_[0] <= $RDSLEVEL_MAX; },
    },
};

has 'debug_mode' => (
    'is' => 'ro',
    'isa' => 'Bool',
    'default' => 0,
);

has 'debug_function' => (
    'is' => 'ro',
    'isa' => 'CodeRef',
    'builder' => '_build_debug_function',
);

has 'raw_output' => (
    'is' => 'rw',
    'isa' => 'Bool',
    'default' => 0,
);

has 'address' => (
    'is' => 'ro',
    'isa' => 'Str',
    'required' => 1,
);

has 'max_tries' => (
    'is' => 'ro',
    'isa' => 'Int',
    'default' => 1,
);

has 'wait_time' => (
    'is' => 'ro',
    'isa' => 'Int', 
    'default' => 1,
);

has 'timeout' => (
    'is' => 'ro',
    'isa' => 'Int',
    'default' => 60,
);

has 'protocol' => (
    'is' => 'ro',
    'isa' => subtype( 'Str' => where { $_ eq 'tcp' || $_ eq 'udp' } ),
    'default' => q/tcp/,
);

has '_socket' => (
    'is' => 'ro',
    'isa' => 'IO::Socket',
    'builder' => '_build_socket',
    'lazy' => 1,
);

subtype 'ArrayRefOfInts', 
    as 'ArrayRef[Int]';

coerce 'ArrayRefOfInts',
    from 'Int',
    via { [ $_ ] };

has 'tcp_ports' => (
    'is' => 'ro',
    'isa' => 'ArrayRefOfInts',
    'coerce' => 1,
    'default' => sub { 
        return [ 10001, 10002 ]; 
    },
);

has 'udp_ports' => (
    'is' => 'ro',
    'isa' => 'ArrayRefOfInts',
    'coerce' => 1,
    'default' => sub { 
        return [ 10003 ]; 
    },
);

has 'dps_format' => (
    'is' => 'ro',
    'isa' => 'Str',
    'default' => '%artist% / %title%',
);

has 'use_rtplus' => (
    'is' => 'ro',
    'isa' => 'Bool',
    'default' => 1,
);

around 'BUILDARGS' => sub {
    my $orig = shift;
    my $class = shift;

    if ( @_ == 1 && !ref $_[0] ) {
        return $class->$orig( 'address' => $_[0], );
    }
    else {
        return $class->$orig( @_ );
    }
};

sub BUILD {
    my $self = shift;
    $self->_debug('Instantiated');
}

sub _send_rds_command {
    my $self = shift;
    my $command = shift;
    my $parameter = shift;

    my $command_string = defined $parameter ? qq/$command=$parameter/ : qq/$command?/;
    $self->_debug(qq/Command string: "$command_string"/);

    my $tries = 0;
    for ( ; ; ) {
        if ( $tries > $self->max_tries ) {
            croak(qq/Maximum tries ($self->max_tries) exceeded sending command/); 
        }
        my @encoder_response = eval { 
            $self->_send($command_string);
        } or do {
            $self->_debug("No response from RDS encoder.  Waiting $self->wait_time s and trying again");
            sleep $self->wait_time;
            next;
        };

        if ($self->raw_output) {
            return [@encoder_response];
        }
        else {
            return $self->_process_encoder_response($command, @encoder_response);
        }
    }
    assert(undef, 'Failed to return encoder response') if DEBUG;
    return undef; # should never reach here.
}

sub _process_encoder_response {
    my ($self, $command, @encoder_response) = @_;

    my $receipt = shift @encoder_response;
    # if echo is turned on, the first line of the RDS encoder's response should be 
    # identical to the string we sent. Otherwise a blank line.
    
    @encoder_response = grep { /\S/ } @encoder_response; # filter out any blank lines

    if ($encoder_response[0] eq 'OK' || $encoder_response[0] eq 'NO') {
        return $encoder_response[0];
    }
    # the remaining lines of the RDS encoder's response should be 'OK' or the value of 
    # the variable (e.g. 'DPSDEFAULT' being read).  In some cases (DST, SCHEDULE, 
    # CALL, PI, ? [literal "?"]) there may be several values returned

    my $ret;
    given ($command) {
        when ([qw/DST SCHEDULE/]) {
            my $value = pop @encoder_response;
            $value =~ s/^$command=//ixsm;
            my $additional_data = [];
            for my $line (@encoder_response) {
                my ($data) = ($line =~ m/\[\d+\](.+)/);
                my $record = {};
                if ($command eq q/SCHEDULE/) {
                    @{$record}{qw/time duration date weekday text/} = split /,/xsm, $data, 5;
                }
                else {
                    @{$record}{qw/start end/} = split /,/xsm, $data, 2;
                }
                push @{$additional_data}, $record;
            }
            $ret = {
                q/value/ => $value,
                q/data/ => $additional_data,
            };
        }
        when ([qw/CALL PI/]) {
            my $additional_data = {};
            for my $line (@encoder_response) {
                my ($key, $value) = split /=/xsm, $line, 2;
                $additional_data->{$key} = $value;
            }
            $ret = {
                q/value/ => $additional_data->{$command},
                q/data/ => $additional_data,
            };
        }
        when ([q{?}]) {
            my $additional_data = {};
            for my $line (@encoder_response) {
                my ($key, $value) = split /=/xsm, $line, 2;
                $additional_data->{$key} = $value;
            }
            $ret = {
                q/value/ => q{},
                q/data/ => $additional_data,
            };
        }
        default { # scalar values
            ($ret = $encoder_response[0]) =~ s/^$command=//ixsm;
        }
    }
    assert(defined($ret), q/return value should be defined in _process_encoder_response/) if DEBUG;
    return $ret;
}

sub _send {
    my ($self, $cmd) = @_;

    local $OUTPUT_RECORD_SEPARATOR = qq/\r\n/;
    local $INPUT_RECORD_SEPARATOR = qq/\r\n/;
    
    $self->_socket->print($cmd);
     
    my @response;
    while (1) {
        my $line = $self->_socket->getline();
        # strip out CR and LF.  Don't chomp() here, though it's tempting; line separators 
        # # will vary from command to command.  Not kidding.
        $line =~ s/[\r\n]//g; 
        if (!defined($line)) {
            croak(qq/read failed: $OS_ERROR/);
        }
        push @response, $line;

        if ($line =~ /^OK$/ || $line =~ /^NO$/) {
            last;
        }

        my $finished;
        given ($cmd) {
            when (/^PI/xsm) {
                $finished = sub { return $_[0] =~ m/^CALL=/ixsm; };
            }
            when (/^RDSLEVEL/xsm) {
                $finished = sub { return $_[0] =~ m/^RDS\sLEVEL=/ixsm; };
            }
            when (/^[?]/xsm) {
                $finished = sub { return $_[0] =~ m/^RDS\sLEVEL=/ixsm; };
            }
            default {
                $finished = sub { return $_[0] =~ m/^$cmd=/ixsm; };
            }
        }
        if ($finished->($line)) {
            last;
        }
    }
    chomp @response;
    return @response;
}

sub _build_socket {
    my $self = shift;
    my $socket;
    foreach my $port (@{$self->tcp_ports}) {
        $socket = IO::Socket::INET->new(
            'PeerAddr' => $self->address,
            'PeerPort' => $port,
            'Proto'    => $self->protocol,
            'Timeout'  => $self->timeout,
        );
        if ($socket) {
            last;
        }
    }
    if (!$socket) {
        croak ( "Failed to connect: $!" );
    }
    return $socket;
}

sub _build_debug_function {
    my $func = sub {
        my ($self, $message) = @_;
        print STDERR qq/$message\n/;
        return 1;
    };
    return $func;
}

sub _debug {
    my ($self, $message) = @_;
    if ($self->debug_mode) {
        return $self->debug_function->($message);
    }
    return 1;
}

sub _disconnect {
    my $self = shift;

    if(!$self->_socket) {
        return;
    }

    $self->_socket->close();

    return 1;
}

sub DEMOLISH {
    my $self = shift;

    $self->_disconnect();

    return 1;
}

sub set_dynamic_program_service_text {
    my ( $self, %params ) = validated_hash(
        \@_,
        'artist' => { 'isa' => 'Str', },
        'title' => { 'isa' => 'Str', },
        'album' => { 'isa' => 'Str', 'optional' => 1, },
        'year' => { 'isa' => 'Int', 'optional' => 1, },
    );
#    'default' => '%Artist% / %Title%',
    my $dps_string = $self->dps_format;
    foreach my $key (keys %params) {
        $dps_string =~ s/%$key%/$params{$key}/g;
    }
    my $response = $self->set_dps($dps_string);
    if ($self->use_rtplus) {
        # do something with RT+
    }
}

sub _set {
    my ($self, $attr, $value) = @_;
    if ($value) {
        if (defined $SUPPORTED_COMMANDS->{$attr}{'validate'}) {
            my $validate = $SUPPORTED_COMMANDS->{$attr}{'validate'};
            if ( ! $validate->($value) ) {
                croak(qq/Invalid value for "$attr": $value/);
            }
        }
    }

    my $response = $self->_send_rds_command($attr, $value);
    if (DEBUG && ref $response) {
        should($self->raw_output, 1) if DEBUG;
        should(ref $response, 'ARRAY') if DEBUG;
        my $found_ok = 0;
        for my $line (@{$response}) {
            if ($line =~ m/OK/xsm) {
                $found_ok = 1;
                last;
            }
        }
        assert($found_ok, qq/Encoder failed to set '$attr' to '$value'/) if DEBUG;  
    }
    # if a valid value was passed, there shouldn't be any case where the encoder says 'NO'.
    should($response, 'OK') if DEBUG; 
    return 1; 
} 

sub _get {
    my ($self, $attr) = @_;
    my $response = $self->_send_rds_command($attr);
    return $response;
}

my $meta = __PACKAGE__->meta;

# Expose the various parameters of the 730 via setters and getters (a la Conway, Perl Best Practices)
foreach my $attr (keys %{$SUPPORTED_COMMANDS}) {
    my $setter_name = sprintf(q/set_%s/, lc($attr));
    my $getter_name = sprintf(q/get_%s/, lc($attr));
    $meta->add_method($setter_name, sub { 
            my ($self, $value) = @_;
            return $self->_set($attr, $value);
        });
    $meta->add_method($getter_name, sub { 
            my ($self) = @_;
            return $self->_get($attr);
        });
}
no Moose;
__PACKAGE__->meta->make_immutable;

1;
