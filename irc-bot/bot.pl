#!/usr/bin/perl -w
package MyBot;
use strict;
use warnings;
use Getopt::Long;
use Proc::PID::File;
use Proc::Daemon;
use YAML qw(LoadFile DumpFile);
use Data::Dumper;
use  base qw(Bot::BasicBot);
use FindBin qw($Bin);
use List::MoreUtils qw(any);
use DBI;


my %options = (
               config_file => "$Bin/bot.conf",
               data_file => "$Bin/data.yaml",
               pid_file_dir => "$Bin",
               log_file => "$Bin/log",
);

my ($data, $super_users, $max_ticketlog_id);
my $dbh;
my $tick_time = 10;
my $need_restart = 0;

my $logfile;

sub log_write{
    my ($type, @msg) = @_;
    print $logfile scalar localtime();
    print $logfile ": $type: ";
    print $logfile @msg;
    print $logfile "\n";
}

sub fatal_loger {
    log_write("error", @_);
}

sub loger {
    log_write("info", @_);
}

sub show_help {
    print <<EOF
Usage:
EOF


}

sub parse_options {
    local @ARGV = @_;
    Getopt::Long::Configure('bundling');
    Getopt::Long::GetOptions
        (
         'h|help' => \&show_help,
         'c|config_file=s' => \$options{config_file},
         'data_file=s' => \$options{data_file},
         'irc_server=s' => \$options{irc_server},
         'irc_port=i' => \$options{irc_port},
         'irc_nick=s' => \$options{irc_nick},
         'irc_password=s' => \$options{irc_password},
         'irc_channel=s@' => \$options{irc_channel},
         'mysql_server=s' => \$options{mysql_server},
         'mysql_username=s' => \$options{mysql_username},
         'mysql_password=s' => \$options{mysql_password},
         'mysql_port=i' => \$options{mysql_port},
         'database=s' => \$options{database},
         'd|daemon' => \$options{daemon},
        );

    if($options{config_file}){
        my $o = LoadFile($options{config_file}) or die "Cannot read config file $options{config_file}\n";
        my @used_config = grep {not defined($options{$_})} keys %options;
        @options{@used_config} = @{$o}{@used_config};
    }

    if($options{data_file}){
        eval {
            $data = LoadFile($options{data_file});
            $super_users = $data->{super_users};
            1;
        }
          or fatal_loger("load data file $options{data_file} failed: $@\n");
    }

}

sub daemonize{

    # check if there is a running script
    die "The bot is already running!\n" if Proc::PID::File->running(dir => $options{pid_file_dir});

    if ($options{daemon}){
        Proc::Daemon::Init({child_STDOUT => ">>$options{log_file}", child_STDERR => ">>$options{log_file}"});
    }

    # after deamon, the pid is changed, so we must create pid file again
    # but maybe the parent process not exit yet, so check and sleep till the parent exit.
    while (Proc::PID::File->running(dir => $options{pid_file_dir})) {
        sleep 1;
    }

}

sub tick{
    my $self = shift;

    # if need restart, restart it first;
    if($need_restart){
        loger("restarting\n");
        close($logfile);
        exec( $^X, $0, @ARGV);
    }

    eval {
        my $sth = $dbh->prepare("select * from tblticketlog where id > $max_ticketlog_id order by id");
        $sth->execute();
        while (my $row = $sth->fetchrow_hashref()) {
            $max_ticketlog_id = $row->{id};
            for my $c (@{$options{irc_channel}}) {
                my $msg_body = "Ticket $row->{tid}: $row->{action} at $row->{date}";
                $self->say( channel => $c,
                            body => $msg_body);
                $self->do_display($c, '!display', 'ticket', $row->{tid});
            }
        }
        1;
    } or fatal_loger("in tick: ", $@);

    return $tick_time;
}

sub do_restart{
    my ($self, $channel) = @_;
    $self->say({'channel' => $channel, body => "I'm restarting"});
    $need_restart = 1;
    $self->schedule_tick(2);
}

sub do_reload{
    my ($self, $channel) = @_;
    $self->say(
               channel => $channel,
               body => "I'm reloading...",
              );
    $dbh->disconnect;
    connect_db();
    $self->say(channel => $channel,
               body => "Done.",
              );
}

sub do_display{
    my ($self, $channel, $command, $arg1, $tid) = @_;

    my $msg = {
               channel => $channel,
              };

    if($arg1 ne 'ticket'){
        $msg->{body} = "Do you mean !display ticket $tid ?";
        $self->say($msg);
        return;
    }


    my $ticket;

    eval {
        my $sth = $dbh->prepare("select * from tbltickets where id = ?");
        $sth->execute($tid);
        $ticket = $sth->fetchrow_hashref();
        1;
    } or do {
        fatal_loger("in display : $@");
        return;
    };

    unless($ticket){
        $msg->{body} = "Sorry, seems there is no such ticket $tid!";
        $self->say($msg);
        return;
    }

    eval {
        my $sth = $dbh->prepare("select * from tblticketreplies where tid = ? order by id desc limit 1");
        $sth->execute($tid);
        my $reply_row = $sth->fetchrow_hashref();
        my $reply;
        if ($reply_row) {
            $reply->{data} = $reply_row->{message};
            if ($reply_row->{userid} != 0){
                my $user = $dbh->selectrow_hashref("select * from tblclients where id = '$reply_row->{userid}'");
                $reply->{user} = "$user->{firstname} $user->{lastname}";
            } else {
                $reply->{user} = "$reply_row->{admin}";
            }

            
        } else {
            $reply->{data} = $ticket->{message};
            $reply->{user} = "";
        }

        if ($ticket->{userid} == 0){
            $ticket->{client} = 'not a registed client';
        }
        else {
            $ticket->{client} = $dbh->selectrow_array("select concat(firstname, ' ', lastname) as name from tblclients where id = $ticket->{userid}");
        }



        $msg->{body} = <<EOF;
Ticket ID: $ticket->{id}
Client: $ticket->{client}
Status: $ticket->{status}
Subject: $ticket->{title}
Last Reply Date: $ticket->{lastreply}
URL: http://test.com/whmcs/admin/supporttickets.php?action=viewticket&id=$ticket->{id}
Last Reply By: $reply->{user}
$reply->{data}

End of ticket.

EOF
        1;
    } or do {
        $msg->{body} = "Opps! Something is wrong";
        fatal_loger("in display: $@");
    };
    $self->say($msg);
}

sub do_adduser{
    my ($self, $channel, $command, $user) = @_;
    my $msg = {
               channel => $channel,
              };
      if(not $user){
          $msg->{body} = "Command format: !adduser username\n";
          $self->say($msg);
          return;
      }
    push @$super_users, $user;
    DumpFile($options{data_file}, $data);
    $msg->{body} = "user $user now is a sumperman!";
    $self->say($msg);

}

sub do_remuser{
    my ($self, $channel, $command, $user) = @_;
    my $msg = {
               channel => $channel,
              };
      if(not $user){
          $msg->{body} = "Command format: !remuser username\n";
          $self->say($msg);
          return;
      }

    @$super_users = grep {$_ ne $user} @$super_users;
    DumpFile($options{data_file}, $data);
    $msg->{body} = "user $user now is not a superman!";
    $self->say($msg);
}

sub connected{
    my $self = shift;
    for my $c (@{$options{irc_channel}}){
        $self->say(
                   channel => $c,
                   body => "Hi, I'm coming again!!!",
                  );
    }

}


sub is_superman{
    my $who = shift;
    return any {$_ eq $who} @$super_users;
}

sub is_super_command{
    my $command = shift;
    my @super_command = ('!restart', '!reload', '!adduser', '!remuser');
    return any {$_ eq $command} @super_command;
}

sub said {
    my ($self, $message) = @_;
    my $msg = $message->{body};
    return undef unless $msg =~ /^!/;
    my $who = $message->{who};

    my @command = split " ", $msg;


    if (is_super_command($command[0]) && ! is_superman($who) ){
        return "sorry $message->{who}, you are not a superman!";
    }

    my %action = 
      (
       "!restart" => \&do_restart,
       "!reload" => \&do_reload,
       "!display" => \&do_display,
       "!adduser" => \&do_adduser,
       "!remuser" => \&do_remuser,
      );

    if(exists $action{$command[0]}){
        $action{$command[0]}->($self, $message->{channel}, @command);
    }
    return undef;
}

sub connect_db {
    my $dsn = "DBI:mysql:database=$options{database};host=$options{mysql_server};port=$options{mysql_port}";
    $dbh = DBI->connect($dsn, $options{mysql_username}, $options{mysql_password},{InactiveDestroy =>1, RaiseError => 1}) or die "cannot connect to mysql\n";

    ($max_ticketlog_id) = $dbh->selectrow_array('select max(id) from tblticketlog');

    
}

parse_options(@ARGV);


#print Dumper(\%options);

print "Bot is running now, please check $options{log_file} for error messages\n";
open($logfile, ">>$options{log_file}") or die "cannot open file $logfile\n";
close($logfile);
daemonize();

open($logfile, ">>$options{log_file}");
select($logfile); $| = 1;


connect_db();


MyBot->new(
      server => $options{irc_server},
      channels => $options{irc_channel},
      nick => $options{irc_nick}, 
      password => $options{irc_password}, #identify password
    )->run();





