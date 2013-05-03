#!/usr/bin/perl
#
use strict;
use warnings;
use feature qw{say switch};
use lib '..';
use English qw/-no_match_vars/;
use IO::Socket::INET;
use Test::More tests => 87;
use Carp qw/croak/;
    
my $VALID_VALUES = {
    q/DPS/ => [q{}, q{LISTENER SUPPORTED 90.9 THE BRIDGE}, q{A} x 128],
    q/DPSDEFAULT/ => [q{}, q{LISTENER SUPPORTED 90.9 THE BRIDGE}, q{A} x 128],
    q/DPSTIMER/ => [0..255],
    q/PARSE/ => [0..9],
    q/DPSS/ => [0..9],
    q/TEXT/ => [q{}, q{KTBG http://ktbg.fm/}],
    q/RTDEFAULT/ => [q{}, q{THIS IS SPARTA!}],
    q/RTTIMER/ => [0..255],
    q/DRTS/ => [0..9],
    q/PI/ => [0..0xffff],
    q/CALL/ => ['KAAA'..'KZZZ', 'WAAA'..'WZZZ', 'WAA'..'WZZ', 'KAA'..'KZZ'],
    q/PTY/ => [0..31],
    q/PTYN/ => [q{}, q{AAA}, q{ABCDEFGH}],
    q/MS/ => [0, 1],
    q/DI/ => [0, 1],
    q/TP/ => [0, 1],
    q/TA/ => [0, 1],
    q/TATIME/ => [0..255],
    q/DHCP/ => [0, 1],
    q/IP/ => q{127.0.0.1},
    q/GATEWAY/ => q{127.0.0.1},
    q/DNS/ => q{127.0.0.1},
    q/SUBNET/ => q{255.0.0.0},
    q/PORT1/ => 10002,
    q/PORT2/ => 10003,
    q/PORT3/ => 10004,
    q/DYNDNS/ => 1,
    q/DYNDNSHOST/ => q{test.dyndns.org},
    q/DYNDNSUSER/ => q{test},
    q/DYNDNSPASS/ => q{test},
    q/TIME/ => q{10:45:00},
    q/DATE/ => q{01/28/14},
    q/UTC/ => q{-6},
    q/DST/ => 1,
    q/CT/ => 1,
    q/ECHO/ => 1,
    q/RDS/ => 1,
    q/UECP/ => 0,
    q/SITE/ => 1,
    q/ENCODER/ => 1,
    q/HEADER/ => 1,
    q/SPEED/ => 9600,
    q/RTP/ => q{01,99,02,99,03,99},
    q/RTPDEFAULT/ => q{01,01,02,03,05,08},
    q/RTPRUN/ => 1,
    q/RTPTOG/ => 1,
    q/SCHEDULE/ => 0,
    q/NETPASS/ => q{foobar},
    q/DELAY/ => 60,
    q/ODA1/ => q{000,1,000000000000},
    q/ODA2/ => q{000,1,000000000000},
    q/RDSLEVEL/ => 0.16,
};
my $INVALID_VALUES = {
    q/DPS/ => q{LISTENER SUPPORTED 90.9 THE BRIDGE},
    q/DPSDEFAULT/ => q{LISTENER SUPPORTED 90.9 THE BRIDGE},
    q/DPSTIMER/ => 60,
    q/PARSE/ => 8,
    q/DPSS/ => 6,
    q/TEXT/ => q{KTBG http://ktbg.fm/},
    q/RTDEFAULT/ => q{THIS IS SPARTA!},
    q/RTTIMER/ => 60,
    q/DRTS/ => 3,
    q/PI/ => q{424C},
    q/CALL/ => q{KTBG},
    q/PTY/ => 23,
    q/PTYN/ => q{AAA},
    q/MS/ => 1,
    q/DI/ => 1,
    q/TP/ => 0,
    q/TA/ => 0,
    q/TATIME/ => 30,
    q/DHCP/ => 0,
    q/IP/ => q{127.0.0.1},
    q/GATEWAY/ => q{127.0.0.1},
    q/DNS/ => q{127.0.0.1},
    q/SUBNET/ => q{255.0.0.0},
    q/PORT1/ => 10002,
    q/PORT2/ => 10003,
    q/PORT3/ => 10004,
    q/DYNDNS/ => 1,
    q/DYNDNSHOST/ => q{test.dyndns.org},
    q/DYNDNSUSER/ => q{test},
    q/DYNDNSPASS/ => q{test},
    q/TIME/ => q{10:45:00},
    q/DATE/ => q{01/28/14},
    q/UTC/ => q{-6},
    q/DST/ => 1,
    q/CT/ => 1,
    q/ECHO/ => 1,
    q/RDS/ => 1,
    q/UECP/ => 0,
    q/SITE/ => 1,
    q/ENCODER/ => 1,
    q/HEADER/ => 1,
    q/SPEED/ => 9600,
    q/RTP/ => q{01,99,02,99,03,99},
    q/RTPDEFAULT/ => q{01,01,02,03,05,08},
    q/RTPRUN/ => 1,
    q/RTPTOG/ => 1,
    q/SCHEDULE/ => 0,
    q/NETPASS/ => q{foobar},
    q/DELAY/ => 60,
    q/ODA1/ => q{000,1,000000000000},
    q/ODA2/ => q{000,1,000000000000},
    q/RDSLEVEL/ => 0.16,
};

BEGIN {
    use_ok(q/Radio::RDS::Inovonics730/);
}

# spawn a listener to emulate the interface to an Inovonics 730 RDS
my $pid = fork;
if (! defined($pid)) {
    die qq/Can't fork: $OS_ERROR/;
}
elsif ($pid == 0) { # child, spawn listener
    listener();
    exit;
}
else { # parent
    my $rds = new_ok( q/Radio::RDS::Inovonics730/ => [{'address' => q/127.0.0.1/, 'debug' => 1}]);
    ok( $rds->address eq q/127.0.0.1/, q/Specifying address in constructor works/ );
    foreach my $key (keys %{$VALID_VALUES}) {
        next if $key eq q/CALL/;
        my $setter = q/set_/ . lc($key);
        my $getter = q/get_/ . lc($key);
        my @values;
        if (ref $VALID_VALUES->{$key}) {
            eval {
                ok( test_all_valid_values($rds, $key), qq{All valid values for $key set/get correctly} );
                1;
            } or warn qq{Set/get failed for $key: $EVAL_ERROR};
        }
        else {
            my $test_value = $VALID_VALUES->{$key};
            ok( $rds->$setter($test_value), qq/$setter returns true with valid value/ ); 
            my $got = $rds->$getter;
            if ( ref $got ) {
                ok( $got->{'value'} eq $test_value, qq/$getter returns valid value that was set/ );
            } 
            else {
                ok( $rds->$getter eq $test_value, qq/$getter returns valid value that was set/ );
            }
        }

        if (ref $INVALID_VALUES->{$key}) {
            @values = @{$INVALID_VALUES->{$key}};
        }
        else {
            @values = ($INVALID_VALUES->{$key});
        }

#        foreach my $test_value (@values) {
#            my $original_value = $rds->$getter;
#            ok( $rds->$setter($test_value) eq 'NO', qq/$setter returns correctly with valid value/ ); 
#            ok( $rds->$getter eq $original_value, qq/$setter did not returns valid value that was set/ );
#        }
    }
    # kill the listener
    kill 'TERM', $pid;
    1;
}

sub listener {
    my $socket = new IO::Socket::INET (
        'LocalHost' => '127.0.0.1',
        'LocalPort' => '10002',
        'Proto'     => 'tcp',
        'Listen'    => 5,
        'Reuse'     => 1,
    ) or croak("Failed to open socket: $OS_ERROR");

    my $state = {
        q/DPS/ => q{LISTENER SUPPORTED 90.9 THE BRIDGE},
        q/DPSDEFAULT/ => q{LISTENER SUPPORTED 90.9 THE BRIDGE},
        q/DPSTIMER/ => 60,
        q/PARSE/ => 8,
        q/DPSS/ => 6,
        q/TEXT/ => q{KTBG http://ktbg.fm/},
        q/RTDEFAULT/ => q{THIS IS SPARTA!},
        q/RTTIMER/ => 60,
        q/DRTS/ => 3,
        q/PI/ => q{424C},
        q/CALL/ => q{KTBG},
        q/PTY/ => 23,
        q/PTYN/ => q{AAA},
        q/MS/ => 1,
        q/DI/ => 1,
        q/TP/ => 0,
        q/TA/ => 0,
        q/TATIME/ => 30,
        q/DHCP/ => 0,
        q/IP/ => q{127.0.0.1},
        q/GATEWAY/ => q{127.0.0.1},
        q/DNS/ => q{127.0.0.1},
        q/SUBNET/ => q{255.0.0.0},
        q/PORT1/ => 10002,
        q/PORT2/ => 10003,
        q/PORT3/ => 10004,
        q/DYNDNS/ => 1,
        q/DYNDNSHOST/ => q{test.dyndns.org},
        q/DYNDNSUSER/ => q{test},
        q/DYNDNSPASS/ => q{test},
        q/TIME/ => q{10:45:00},
        q/DATE/ => q{01/28/14},
        q/UTC/ => q{-6},
        q/DST/ => {
            'value' => 1,
            'data' => [
                q{[0]11/03/13,03/09/14},
                q{[1]11/02/14,03/08/15},
                q{[2]11/01/15,03/13/16},
                q{[3]11/06/16,03/12/17},
                q{[4]11/05/17,03/11/18},
                q{[5]11/04/18,03/10/19},
                q{[6]11/03/19,03/08/20},
                q{[7]11/01/20,03/14/21},
                q{[8]11/07/21,03/13/22},
                q{[9]11/06/22,00/00/00},
            ],
        },
        q/CT/ => 1,
        q/ECHO/ => 1,
        q/RDS/ => 1,
        q/UECP/ => 0,
        q/SITE/ => 1,
        q/ENCODER/ => 1,
        q/HEADER/ => 1,
        q/SPEED/ => 9600,
        q/RTP/ => q{01,99,02,99,03,99},
        q/RTPDEFAULT/ => q{01,01,02,03,05,08},
        q/RTPRUN/ => 1,
        q/RTPTOG/ => 1,
        q/SCHEDULE/ => { 
            'value' => 0, 
            'data' => [ 
                q{[01]23:50:00,000,00/00,S------,LISTENER SUPPORTED 90.9 THE BRIDGE},
                q{[02]10:49:04,000,04/26,-------,please drive safely},
                q{[03]10:49:13,000,04/26,-------,your contribution matters},
                q{[04]10:49:23,000,00/00,------S,weekend edition},
                q{[05]15:10:34,000,00/00,-M---F-,Thanks for listening},
            ],
        },
        q/NETPASS/ => q{foobar},
        q/DELAY/ => 60,
        q/ODA1/ => q{000,1,000000000000},
        q/ODA2/ => q{000,1,000000000000},
        q/RDSLEVEL/ => 0.16,
    };
    my $client_socket; 
   
    open my $fh, '>', 'session.log'; 
    while (1) {
        local $INPUT_RECORD_SEPARATOR = qq{\r\n};
        local $OUTPUT_RECORD_SEPARATOR = qq{\r\n};
        if (!$client_socket) { 
            $client_socket = $socket->accept;
            $client_socket->autoflush(1);
            say $fh q{client connected};
        } else {
            my $response;
            my $cmd = <$client_socket>;
            if (!$cmd) { # assume client has disconnected
                say $fh q{client disconnected};
                $client_socket->close();
                $client_socket = undef;
                next;
            }
            chomp $cmd;
            print $fh $cmd;
            if ($cmd =~ /[?]$/) { # query
                my $key = uc substr $cmd, 0, -1;
                if (defined $state->{$key}) {
                    given ($key) {
                        when (q/RDSLEVEL/) {
                            $response = qq/RDS LEVEL=$state->{$key}Vpp/;
                        }
                        when ([qw/DST SCHEDULE/]) {
                            $response = join $OUTPUT_RECORD_SEPARATOR, @{$state->{$key}{'data'}}, qq/$key=$state->{$key}{'value'}/; 
                        }
                        when ([qw/PI CALL/]) {
                            $response = join $OUTPUT_RECORD_SEPARATOR, qq/PI=$state->{'PI'}/, qq/CALL=$state->{'CALL'}/;
                        }
                        default {
                            $response = qq/$key=$state->{$key}/;
                        }
                    }
                }
                else {
                    $response = q/NO/;
                }
            } 
            elsif ($cmd =~ m/=/xsm) {
                my ($key, $value) = split /=/xsm, $cmd, 2;
                $key = uc $key;
                if (defined $state->{$key}) {
                    if ( ! ref $state->{$key}) {
                        $state->{$key} = $value;
                    } 
                    else {
                        $state->{$key}{'value'} = $value;
                    }
                }
                $response = q/OK/;
            }
            else {
                $response = q/NO/;
            }
            $client_socket->print($cmd);
            $client_socket->print($response);
            print $fh $cmd;
            print $fh $response;
            $fh->flush;
        }
    }
}

#all_ok($rds, $key, qq{$setter returns true with valid value, $getter returns valid value that was set});
sub test_all_valid_values {
    my ($rds, $key, $message) = @_;

    my $setter = q/set_/ . lc($key);
    my $getter = q/get_/ . lc($key);

    foreach my $value (@{$VALID_VALUES->{$key}}) {
        if ($key eq 'PI') {
            $value = sprintf('%04x', $value);
        }
        my $set_ok = eval {
            $rds->$setter($value);
            1;
        } or croak(qq/$setter($value) failed: $EVAL_ERROR/);

        my $got = eval { 
            $rds->$getter;
        };
        if (! defined $got ) {
            if ($EVAL_ERROR) {
                croak(qq/$getter() threw an exception: $EVAL_ERROR/);
            }
            else {
                croak(qq/$getter() returned undef/);
            }
        }
        if ($set_ok) {
            if (ref $got) { 
                if ($got->{'value'} !~ $value) {
                    croak(qq/$getter failed to return value set by $setter. "$got" !~ "$value"/);
                }
            }
            else {
                if ($got !~ $value) {
                    croak(qq/$getter failed to return value set by $setter. "$got" !~ "$value"/);
                }
            }
        }
    }
    return 1;
}
END { 
    kill 'TERM', $pid if ($pid);
}
