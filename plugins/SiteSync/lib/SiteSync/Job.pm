package SiteSync::Job;

use strict;
use warnings;
use Data::Dumper;

use base qw( TheSchwartz::Job );

# use MT::Log::Log4perl qw( l4mtdump ); our $logger = MT::Log::Log4perl->new();

sub new {
    my $class = shift;
    my ( %param ) = (
        priority => 5,           # Mid-level priority is good
        uniqkey  => 'site_sync', # FIXME Handle per-blog sync
        @_
    );

    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    unless ( $param{funcname} ) {
        # Get job funcname from the registry
        my $task_workers = MT->registry('task_workers') || {};
        if ( my $sync_task = $task_workers->{site_sync} ) {
            $param{funcname} = $sync_task->{class};
        }
    }

    # $logger->debug('PARAMS: ', l4mtdump(\%param));

    my $job = $class->SUPER::new(
        %param
    );

    # $logger->debug('Job: ', l4mtdump($job));
    return $job;
}

1;