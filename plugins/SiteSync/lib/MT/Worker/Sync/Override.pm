package MT::Worker::Sync::Override;

use strict;
use warnings;
use base qw( TheSchwartz::Worker );

# use MT::Log::Log4perl qw( l4mtdump ); our $logger = MT::Log::Log4perl->new();

sub work {
    my $class                = shift;
    my TheSchwartz::Job $job = shift;
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    $job->debug("Native MT::Worker::Sync job disabled by SiteSync");
    $job->completed();
}

1;