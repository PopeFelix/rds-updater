#!/usr/bin/perl

###############################
# RDS Updater
# Updates RDS via TCP/IP from Simian logs
# Author: Kit Peters <cpeters@ucmo.edu>
# Date: 24 May 2011
# Version: 2.1
###############################
use strict;
use warnings;
use English '-no_match_vars';
use Fcntl;
use IO::File;
use IO::Handle;
use IO::Socket::INET;
use Text::CSV_XS;
use File::ReadBackwards;
use POSIX qw/strftime/;
use Readonly;
use Carp qw/croak/;
use constant {
    SOCK_SHUTDOWN_BOTH    => 2,
    TRACK_CODE_POSITION   => 6,
    TRACK_TYPE_POSITION   => 7,
    ARTIST_TITLE_POSITION => 8,
    DO_FORK               => 1,
};

Readonly my $LOGFILE              => '/var/log/update-rds.log';
Readonly my $LOG_DIR              => q|/mnt/bsilogs|;
Readonly my $RDS_HOST             => q/153.91.87.70/;
Readonly my @RDS_PORTS_TCP        => ( 10001, 10002 );
Readonly my @RDS_PORTS_UDP        => (10003);
Readonly my $PID_FILE             => q|/var/run/update-rds.pid|;
Readonly my $CHECK_INTERVAL       => 5;
Readonly my $DPS_DEFAULT_FAILSAFE => q/LISTENER SUPPORTED 90.9 THE BRIDGE/;
Readonly my $SOCKET_TIMEOUT       => 60;
Readonly my $MAX_RDS_CMD_TRIES    => 10;
Readonly my $RDS_CMD_WAIT_TIME    => 1;

my $debug = shift;
if ( $debug && $debug !~ /-d/ ) {
    $debug = undef;
}

my $rds_socket;
my $pid = 0;

main();

sub main {
    handle_fork();
    logwrite("Startup");
    my $filename = shift;
    $filename ||= "$LOG_DIR/" . strftime( '%y%m%d.lst', localtime(time) );

    my $dps_default     = '';
    my $dps_string      = '';
    my $last_dps_string = '';
    $rds_socket =

      eval { get_rds_socket( $RDS_HOST, \@RDS_PORTS_TCP, 'tcp' ); } or do {
        error(qq/Open RDS socket failed: $EVAL_ERROR/);
      };

    for ( ; ; ) {

        eval {
            $dps_default = get_dps_default() || $DPS_DEFAULT_FAILSAFE;
            1;
        } or do {
            logwrite(
qq/WARNING: Failed to get DPS default from RDS host $RDS_HOST: $EVAL_ERROR/
            );
        };

        $last_dps_string = $dps_string;
        eval {
            $dps_string = get_dps_string($filename) || $dps_default;
            1;
        } or do {
            logwrite(
qq/WARNING: Failed to get DPS string from "$filename": $EVAL_ERROR/
            );
        };

        if ( $dps_string eq $last_dps_string ) {
            debug(q/DPS string unchanged/);
        }
        else {
            eval {
                send_dps_string($dps_string);
                logwrite(qq/Sent DPS string "$dps_string"/);
            } or do {
                logwrite(
qq/WARNING: Failed to send DPS string to encoder: $EVAL_ERROR/
                );
                next;
            };
        }
        debug("Sleeping $CHECK_INTERVAL");
        sleep $CHECK_INTERVAL;
        debug("Slept $CHECK_INTERVAL");
    }
}

END {
    if ( $pid == 0 && -f $PID_FILE ) {
        unlink $PID_FILE;
    }
    if ($rds_socket) {
        $rds_socket->shutdown(SOCK_SHUTDOWN_BOTH);
        $rds_socket->close();
    }
}
1;

sub logwrite {
    my $date = strftime( '%d %b %Y %T', localtime(time) );
    my $message = shift;

    my $fh;
    if ($debug) {
        open $fh, q/>-/;    # stdout
    }
    else {
        open $fh, qq/>>$LOGFILE/,
          or die qq/Can't open $LOGFILE for writing: $!/;
    }
    print $fh "[$date] $message\n";
}

sub debug {
    my $message = shift;
    if ($debug) {
        logwrite("DEBUG: $message");
    }
}

sub error {
    my $message = shift;
    logwrite("ERROR: $message");
    croak($message);
}

sub get_dps_string {
    my $filename = shift or die q/Usage: get_dps_string(<filename>)/;

    my $bw = File::ReadBackwards->new($filename) or do {
        die("Can't open $filename for reading: $!");
    };
    debug("Opened Simian logfile \"$filename\"");

    my $csv = Text::CSV_XS->new(
        {
            'sep_char'           => '|',
            'binary'             => 1,
            'allow_loose_quotes' => 1
        }
    );

    my $line;
    my @fields;

    # read the file until we find a non-macro line
    for ( ; ; ) {
        $line = $bw->readline;
        if ( $csv->parse($line) ) {
            @fields = $csv->fields;
            if (   $fields[TRACK_TYPE_POSITION] ne 'MACRO'
                && $fields[TRACK_TYPE_POSITION] ne 'COMMENT' )
            {
                last;
            }
        }
    }

    my $dps_string;
    if ( $fields[TRACK_CODE_POSITION] =~ /^[A-Z0-9]{7}$/ )
    {    # music tracks are exactly 7 alphanumeric characters
        my ( $artist, $title ) = split /\s{2,}/, $fields[ARTIST_TITLE_POSITION];
        $title  ||= '';
        $artist ||= '';
        $dps_string = "$artist / $title";

        if ( $artist !~ /\S/ || $title !~ /\S/ ) {
            $dps_string = "$artist $title";
        }
    }
    elsif ($fields[TRACK_TYPE_POSITION] =~ /^NPRCD$/
        || $fields[ARTIST_TITLE_POSITION] =~ /NPR Newscast/i )
    {    # NPR
        $dps_string = "NPR NEWS";
    }
    if ($dps_string) {
        debug(qq/Got DPS string: "$dps_string"/);
    }
    else {
        debug(qq/No DPS string from line: "$line"/);
    }
    return $dps_string;
}

sub get_rds_socket {
    my $host  = shift;
    my $ports = shift;
    my $proto = shift || 'tcp';
    my $sock;
    for my $port (@$ports) {
        $sock = new IO::Socket::INET(
            'PeerAddr' => $host,
            'PeerPort' => $port,
            'Proto'    => $proto,
            'Timeout'  => $SOCKET_TIMEOUT,
        );
        if ($sock) {
            return $sock;
        }
        logwrite("Failed to open TCP socket to $RDS_HOST:$port: $!\n");
    }
    if ( !$sock ) {    # no socket on any supplied port
        $DB::single = 1;
        die(    qq/No available $proto sockets to host $RDS_HOST, ports /
              . join( ', ', @$ports )
              . qq/: $@/ );
    }
}

# note: assumes echo is active on the remote RDS encoder
sub send_rds_command {
    my $command = shift;

    local $/ = "\r\n";
    local $\ = "\r\n";

    chomp $command;
    my $tries = 0;
    for ( ; ; ) {
        if ( $tries > $MAX_RDS_CMD_TRIES ) {
            error(
qq/Maximum tries ($MAX_RDS_CMD_TRIES) exceeded attempting to send command "$command"/
            );
        }
        print $rds_socket $command;

# if echo is turned on, the first line of the RDS encoder's response should be identical to the string we sent. Otherwise a blank line.
        my $receipt = <$rds_socket>;
        if ( !defined $receipt ) {
            debug(
"No response from RDS encoder.  Waiting $RDS_CMD_WAIT_TIME s and trying again"
            );
            sleep $RDS_CMD_WAIT_TIME;
            next;
        }
        chomp($receipt);
        $receipt =~ s/\r$//;  # receipt may have a trailing CR, even after chomp
        debug("Got receipt: \"$receipt\"");

# the second line of the RDS encoder's response should be 'OK' or the value of the variable (e.g. 'DPSDEFAULT' being read).
        my $response = <$rds_socket> || '';
        chomp($response);
        if ($response) {
            return $response;
        }
    }
}

sub get_dps_default {
    my $rds_response;
    eval {
        $rds_response = send_rds_command('DPSDEFAULT?');
        1;
    } or do {
        $DB::single = 1;
        die qq/RDS command failed: $EVAL_ERROR/;
    };
    if ( $rds_response =~ /^DPSDEFAULT/ ) {
        ( my $dps_default = $rds_response ) =~ s/^DPSDEFAULT=//;
        return $dps_default;
    }
    $DB::single = 1;
    die(qq/Unexpected response from RDS encoder: "$rds_response"/);
}

sub send_dps_string {
    my $string = shift;
    my $rds_response;
    eval {
        $rds_response = send_rds_command(qq/DPS=$string/);
        1;
    } or do {
        $DB::single = 1;
        die qq/failed to send RDS command: $EVAL_ERROR/;
    };
    if ( $rds_response !~ /OK/ ) {
        $DB::single = 1;
        die(qq/Unexpected response from RDS encoder: "$rds_response"/);
    }
}

sub handle_fork {
    if (DO_FORK) {
        $pid = fork();
        if ( !defined($pid) ) {
            die "Could not fork: $!";
        }
        if ($pid) {
            open my $pid_fh, ">$PID_FILE" or do {
                error("Failed to open PID file \"$PID_FILE\": $!");
                die();
            };
            print $pid_fh "$pid\n";
            close $pid_fh;
            exit;
        }

        if ( -f $PID_FILE ) {
            $pid = `cat $PID_FILE`;
            chomp($pid);
            if ( -f qq|/proc/$pid| ) {
                error("RDS updater already running with PID $pid.  Exiting.");
                die;
            }
            else {
                logwrite("Deleting stale pid file.");
                unlink($PID_FILE);
            }
        }
    }
}
