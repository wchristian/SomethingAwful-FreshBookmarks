use strictures;

use 5.010;
use SomethingAwful::Forums;
use Mozilla::CA;    # necessary to be able to login
use IO::All -binary, -utf8;
use JSON qw' encode_json decode_json ';
use Fcntl qw(:flock);
use POSIX;

=head1 DESCRIPTION

Scrapes the SA bookmarked threads of the logged in user, and prints details
(new post count, title, link) for those that have new posts and have been added
since the last run or had no posts on the last run; effectively picking out the
ones you're actually following.

Throws errors when previous runs still exist, or the lockfile cannot be locked.

Requires a file called ".salogin" with the login details separated by a newline.

Uses temporary files: $0.pid, .bookmarks and .cookies

Can be dumped into a cron file with the email option set, resulting in emails
being sent when actively followed threads have new posts.

=head1 INSTALLATION

Follow the instructions to install this module:

https://github.com/ugexe/SomethingAwful--Forums

Then additionally install: Mozilla::CA IO::All JSON

=cut

our $PID_LOCK;

BEGIN {
    die "ERROR: Pidfile already exists!\nBye!\n" if -e "$0.pid"  and !open $PID_LOCK, "+<$0.pid";
    die "ERROR: Unable to lock pidfile!\nBye!\n" if !-e "$0.pid" and !open $PID_LOCK, "+>$0.pid";
    die "ERROR: Unable to get exclusive lock on pidfile!\nBye!\n" if !flock $PID_LOCK, LOCK_EX | LOCK_NB;

    seek $PID_LOCK, 0, 0;
    print $PID_LOCK $$;
    truncate $PID_LOCK, tell $PID_LOCK;
}

my ( $username, $password ) = split /\n/, io( ".salogin" )->all;

my $SA = SomethingAwful::Forums->new;

my $cookies             = ".cookies";
my $probably_empty_size = 30;           # this number may need to be increased if it turns out some cookies
                                        # have no credentials even above this size
$SA->mech->cookie_jar( HTTP::Cookies->new( file => $cookies, autosave => 1, ignore_discard => 1 ) );
$SA->login( username => $username, password => $password ) if !-e $cookies or -s $cookies < $probably_empty_size;

my $page = 0;
my @threads;
while ( 1 ) {
    $page++;
    my $res = $SA->mech->get( URI->new_abs( "/bookmarkthreads.php?pagenumber=$page", $SA->base_url ) );
    die "Forum fetch failed! forum_id: bookmarks details: " . $res->decoded_content if !$res->is_success;
    last
      unless my $scrape = $SA->forum_scraper->scrape( $res->decoded_content, $SA->base_url )->{threads};
    push @threads, @{$scrape};
}
my %by_id_new = map { $_->{id} => $_ } @threads;

my $bm = io ".bookmarks";
my %by_id_old = %{ $bm->exists ? decode_json $bm->all : {} };

say "$by_id_new{$_}{unread} new posts in '$by_id_new{$_}{title}'\n$by_id_new{$_}{last_post}{uri}"
  for grep { $by_id_new{$_}{unread} and ( !$by_id_old{$_} or !$by_id_old{$_}{unread} ) } keys %by_id_new;

# the JSON encoder doesn't like the URI objects and we don't need them anymore
delete $_->{uri}, delete $_->{last_post}{uri} for values %by_id_new;

$bm->print( encode_json \%by_id_new );

exit;
