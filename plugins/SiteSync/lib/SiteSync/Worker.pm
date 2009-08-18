# Movable Type (r) (C) 2001-2009 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id: Sync.pm 3455 2009-02-23 02:29:31Z auno $

package SiteSync::Worker;

use strict;
use warnings;
use base qw( TheSchwartz::Worker );
use Time::HiRes qw(gettimeofday tv_interval);
use TheSchwartz::Job;
use MT::FileInfo;
use MT::Util qw( log_time );
use SiteSync;

# use MT::Log::Log4perl qw( l4mtdump ); our $logger = MT::Log::Log4perl->new();

my $MARK = '-'x30;

sub work {
    my $class                = shift;
    my TheSchwartz::Job $job = shift;
    my %args                 = @{   $job->arg || [] };
    my $blog_id              = $args{blog_id} || 0;
    my $last                 =    $args{last} || 0;
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    MT->run_callbacks('sitesync_pre_sync', {
        worker_class => $class,
        blog_id => $blog_id,
        last => $last,
        $job => $job
    });

    # DO SYNC
    my $sync_set = [gettimeofday];
    if ( SiteSync->sync_now() ) {
        MT::TheSchwartz->debug("-- sync complete (" . sprintf("%0.02f", tv_interval($sync_set)) . " seconds)");
    }

    # $job->debug("SiteSync $MARK SITE SYNCHED $MARK");
    $job->completed();

    MT->run_callbacks('sitesync_post_sync', {
        worker_class => $class,
        blog_id => $blog_id,
        last => $last,
        $job => $job
    });

    require MT::Request;
    unless ( $last ) {
        MT::TheSchwartz->debug("SiteSync - Submitting low priority cleanup job");
        require SiteSync;
        SiteSync->queue_sync({
            priority  => 1,
            arg       => [ %args, last => 1 ],
            run_after => time() + 30,  # 30-second delay on the cleanup sync
        });
        #--------------------------------------------------
        # require MT::TheSchwartz;
        # require TheSchwartz::Job;
        # $job = TheSchwartz::Job->new();
        # $job->funcname($class);
        # my $uniqkey = 'sitesync-blog-'.$blog_id;
        # $job->uniqkey( $uniqkey );
        # $job->arg([ last => 1, blog_id => $blog_id  ]);
        # $job->priority( 1 );
        # $job->run_after(time() + 30);  # 30-second delay on the cleanup sync
        # MT::TheSchwartz->insert($job);
        # MT::TheSchwartz->debug("SiteSync $MARK Low priority cleanup job submitted $MARK");
    }
    return;

}

sub grab_for { 60 }
sub max_retries { 10 }
sub retry_delay { 60 }

1;
