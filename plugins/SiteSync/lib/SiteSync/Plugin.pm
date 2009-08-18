package SiteSync::Plugin;

use strict;
use warnings;
use Data::Dumper;

# use MT::Log::Log4perl qw( l4mtdump ); our $logger = MT::Log::Log4perl->new();

use SiteSync;

*file_added   = \&needs_sync;
*file_removed = \&needs_sync;
*file_moved   = \&needs_sync;

sub instance { MT->component('SiteSync') }

sub post_init {
    my ($cb, $mt, $mt_param) = @_;
    my $plugin               = $cb->plugin;
    my $task_workers         = $mt->registry('task_workers') || {};
    my $cfg                  = MT->config;
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    if (   $cfg->RsyncPath
        && $cfg->RsyncOptions
        && $cfg->SyncTarget
        && $cfg->DefaultSiteRoot ) {
        
        $plugin->{enabled} = 1;
        if ( my $mt_sync = $task_workers->{mt_sync} ) {
            $mt_sync->{class} = 'MT::Worker::Sync::Override';
            $mt_sync->{label} = 'The SiteSync-overridden MT sync task worker';
        }
    }
    else {
        $plugin->{enabled} = 0;
        $task_workers->{site_sync} = undef;
    }
}

sub needs_sync {
    my ($cb, @args) = @_;
    my $plugin      = $cb->plugin;
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    return unless $plugin->{enabled};

    # If we've already been notified 
    return if $plugin->{__post_run_callback};

    # $logger->debug(
    #     "SiteSync SITE FLAGGED AS NEEDING SYNC - %s"
    #     .$cb->name
    # );

    my $app = MT->instance;
    if ( $app->isa('MT::App') ) {
        $plugin->{__post_run_callback} = MT->add_callback(
            ref($app).'::post_run', # Create sync job after mode execution
            1,                      # Low priority
            $plugin, 
            \&cb_cms_post_run
        );
    }
    # Non-MT::App processes - must be using run-periodic-tasks
    else {
        SiteSync->queue_sync();
    }
}

sub cb_cms_post_run {
    my ($cb, $app, @args) = @_;
    my $plugin = $cb->plugin;
    # $logger ||= MT::Log::Log4perl->new(); $logger->trace();

    return unless $plugin->{enabled};

    # my $blog_id = $app->blog->id;
    SiteSync->queue_sync();
    $plugin->{__post_run_callback} = undef;
}

1;