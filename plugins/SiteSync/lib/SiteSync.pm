package SiteSync;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday tv_interval);
use MT::Util qw( log_time );

# use MT::Log::Log4perl qw( l4mtdump ); our $logger = MT::Log::Log4perl->new();

my %default_worker;
sub init_default_worker_params {
    my $class = shift;
    unless ( keys %default_worker ) {
        %default_worker = (
            priority => 5,           # Mid-level priority is good
            uniqkey  => 'site_sync', # FIXME Handle per-blog sync
        );
        # Get job funcname from the registry
        my $task_workers = MT->registry('task_workers') || {};
        if ( my $sync_task = $task_workers->{site_sync} ) {
            $default_worker{funcname} = $sync_task->{class};
        }
    }
}

sub queue_sync {
    my $class = shift;
    my $args = shift || {};
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    $class->init_default_worker_params();
    
    require TheSchwartz::Job;
    my $job = TheSchwartz::Job->new( %default_worker, %$args );

    require MT::TheSchwartz;
    MT::TheSchwartz->insert($job);
    # $logger->debug("SiteSync SUBMITTED JOB REQUEST FOR SITE SYNC");

    return $job;
}

sub sync_now {
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();
    
    my $rsync_cmd = MT->config("RsyncPath") || "rsync";
    my $rsync_opt = MT->config('RsyncOptions') || '';
    my @targets   = MT->config('SyncTarget');
    my $source    = MT->config('DefaultSiteRoot');

    for my $target ( @targets ) {
        MT::TheSchwartz->debug("Syncing files to $target...");
        my $cmd = "$rsync_cmd $rsync_opt $source $target";
        MT::TheSchwartz->debug( 'Syncing with: '.$cmd );
        # $logger->debug('rsync: ', $cmd);

        my $start = [gettimeofday];
        my $res = `$cmd` || '';
        if ( $res ) {
            # $logger->debug($res);
            MT::TheSchwartz->debug($res);
        }

        # Handle logging and error conditions
        my $exit = $? >> 8;
        if ($exit != 0) {
            # TBD: notification to administrator
            # At the very least, log to MT activity log.
            my $err = 'Error during rsync of files...<br />'
                        ."\nCommand: $cmd\n";

            MT->log({
                message => "Site Sync: Synchronization failed to $target",
                level => MT::Log::ERROR(),
                category => 'sitesync',
                metadata => "Command: $cmd\nOutput: ".$res,
            });
        } else {
            my $elapsed = sprintf("done! (%0.02fs)", tv_interval($start));
            my $metadata = ($res ? $res."\n" : '')
                         . log_time() 
                         . ' '
                         . MT->translate('Done syncing files to [_1] ([_2])',
                                        $target, $elapsed);
            MT->log({
                message => MT->translate('Files synchronization to [_1] complete',
                                        $target),
                metadata => $metadata,
                category => "sync",
                level => MT::Log::INFO(),
            });
            MT::TheSchwartz->debug($elapsed);
        }
    }
}

1;
