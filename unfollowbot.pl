#!/usr/bin/env perl
use strict;
use warnings;
use Net::Twitter;
use List::Compare;
use feature 'say';
use File::HomeDir;
use Config::Simple;
# please use another KEY+SECRET for your fork
use constant C_KEY => 'cv5PWaCvTcirEihc1gvYA';
use constant C_SECRET => 'fkwRkjFvstVIwIzajksc2HtownmSKN2T1IDIqkYZk';


my %LAST;

my $t = Net::Twitter->new(
    traits => [ qw( API::REST RetryOnError OAuth RetryOnError ) ],
    # we are a bot, our life is meaningless without response. so try desperately:
    max_retries => 0,
    consumer_key => C_KEY,
    consumer_secret => C_SECRET,
);

my $config = Config::Simple->new(syntax => 'ini');
my $config_file = $ENV{CONFIG} || File::HomeDir->my_home . '/.unfollowbot.conf';

if (-e $config_file)
{
    $config->read($config_file);

    $t->access_token($config->param('token'));
    $t->access_token_secret($config->param('secret'));
}

unless ($t->authorized) {
    say "authorize app at ", $t->get_authorization_url, " and enter PIN:";
    my $verifier = <STDIN>;
    chomp $verifier;

    my ($token, $secret, $uid, $name) = $t->request_access_token(verifier => $verifier);
    $config->param(token => $token);
    $config->param(secret => $secret);
    $config->write($config_file);
}

#$t->update(scalar localtime() . ": starting to watch my watchers watchers stop watching my watchers")
#    or die 'Could not tweet startup';

sub followers
{
    my %param = @_;
    my @followers;

    print "getting followers: ";
    my $cursor = -1;
    while ($cursor)
    {
        my $r;
        print $cursor;
        do
        {
            eval
            {
                $r = $t->followers_ids({ cursor => $cursor, %param });
                $cursor = $r->{next_cursor};
            };
            if ($@)
            {
                warn $@->error;
                sleep 60;
            }
        } while ($@);

        push @followers, @{ $r->{ids} };

        print "->" if $cursor;
    }
    print "\n";
    return @followers;
}

while (1)
{
    for my $id (followers())
    {
        say $id;

        my @followers = followers(id => $id);

        $LAST{$id} = \@followers and next unless ($LAST{$id});

        my $lc = List::Compare->new($LAST{$id}, \@followers);
        say "\tnew followers: " . join ', ', $lc->get_Ronly;

        for my $unfollow_id ($lc->get_Lonly)
        {
            my $friend = eval { $t->show_user($id) } or next;

            # show_user fails -> most likely spammer/disabled account
            my $unfollow = eval { $t->show_user($unfollow_id) } or next;

            my $tweet = '@' . $unfollow->{screen_name} 
                . ' has unfollowed @' . $friend->{screen_name};

            say "\t$tweet";
            eval { $t->update($tweet) } # rare case: someone unfollow,
                                        # follow and unfollow again
                                        # -> twitter disallow duplicated
                                        # tweets but thats ok with us
        }

        $LAST{$id} = \@followers;
    }
    sleep 60;
}
