package MT::Plugin::SiteSync;
# A plugin for Movable Type
# Copyright 2007, All rights reserved
# $Id: SiteSync.pl 199 2007-10-31 16:17:29Z jay $
use strict; use 5.006; use warnings; use diagnostics; use Data::Dumper;
use Carp qw(croak confess);

use constant DEBUG => 0;

our $VERSION = '1.0'; #$Revision: 199 $
# use version; our $VERSION = qv(sprintf "1.0_%d", q!$Revision: 199 $! =~ /(\d+)/g);

# TODO Remove rsync options and bar rsync command line

use Time::HiRes qw(gettimeofday tv_interval);
use MT 3.2;   # requires MT 3.2 or later
use MT::Plugin;
use base 'MT::Plugin';

our ($plugin, $PLUGIN_MODULE, $PLUGIN_KEY);
MT->add_plugin($plugin = __PACKAGE__->new({
    name            => 'Site Sync',
    author_name     => 'Jay Allen, Textura Design',
    author_link     => 'http://texturadesign.com',
    description     => 'Allows you to synchronize your published site to '
                       .'another location on the local server or a remote one.',
    version         => $VERSION,
    key             => plugin_key(),
    system_config_template => 'system_config.tmpl',
    settings => new MT::PluginSettings([
        ['last_sync_time',          { Default => 0  }],
        ['last_sync_user',          { Default => 0  }],
        ['delete_orphans',          { Default => 0 }],
        ['rsync_command',           { Default => '' }],
        ['remote_user',             { Default => '' }],
        ['remote_server',           { Default => '' }],
        ['destination_path',        { Default => '' }],
        ['source_path',             { Default => '' }],
        ['rsync_options',           { Default => '-auvz'}],
        ['authorized_users',        { Default => 'sysadmin' }],
        ['authorized_usernames',    { Default => '' }],
    ]),
    callbacks => {
         'MT::App::CMS::AppTemplateSource.list_blog' => {
             priority => 2,
             code => \&add_sitesync_menu
         },         
         'MT::App::CMS::AppTemplateSource.header' => {
             priority => 2,
             code => \&add_header_elements
         },         
    },
    app_methods => {
        'MT::App::CMS' => {
            'sitesync'    => \&sitesync,
            'do_sitesync' => \&do_sitesync,
        }
    },
}));

sub plugin_module   {
    ($PLUGIN_MODULE = __PACKAGE__) =~ s/^MT::Plugin:://;
    return $PLUGIN_MODULE; }

sub plugin_key      {
    ($PLUGIN_KEY = lc(plugin_module())) =~ s/\s+//g;  return $PLUGIN_KEY; }

our ($mtlog);
sub get_logger {
    my $cat = shift;
    require MT::Log::Log4perl;
    return MT::Log::Log4perl->get_logger($cat ? $cat :        
        join("::", plugin_module(), __PACKAGE__));
}


sub add_header_elements {
	my ($cb, $app, $tmpl) = @_;
    my $logger = get_logger();
    $logger->marker();
    (my $static = $app->static_path) =~ s!/$!/images!;
    my $css = <<'EOD';
    .box ul.nav li#nav-sitesync
        { background-image: url(%s/ani-rebuild.gif); }
    .box ul.nav li#nav-sitesync-list
        { background-image: url(%s/nav_icons/color/entries.gif); }
    .box ul.nav li#nav-sitesync-log
        { background-image: url(%s/nav_icons/color/log.gif); }
EOD
    $app->tmpl_append(
        $tmpl, 'head', 'style',sprintf($css, $static, $static, $static)
    );
}

sub add_sitesync_menu {
	my ($cb, $app, $tmpl) = @_;
    my $logger = get_logger();
    $logger->marker();
    
    my $newsbox = q(<div class="box" id="news-box">
<h4><a href="<TMPL_VAR NAME=MT_NEWS>?v=<TMPL_VAR NAME=MT_PRODUCT_CODE><TMPL_VAR NAME=MT_VERSION>"><MT_TRANS phrase="Movable Type News"></a> &#187;</h4>
<div class="inner">
<TMPL_VAR NAME=NEWS_HTML>
</div>
</div>);

    $newsbox = quotemeta($newsbox);

    my $log_uri = $app->uri(mode => 'search_replace', args => { _type => 'log', do_search => 1, search => 'Site Sync:' });

    my $replace = is_authorized($app) ? <<"EOD" : '';
    <script type="text/javascript">
    <!--
        function doSiteSync() {
            if (confirm("Are you sure you want to synchronize your site?")) {
                return true;
            }
            return false;
        }
    -->
    </script>

    <div class="box" id="sitesync-box">
    <h4 style="background-color: #052b76; color: #eee">BNN Site Synchronization</h4>
    <div class="inner">
        <ul class="nav">
            <li id="nav-sitesync-list">
                <a href="#" onclick="openDialog(this.form, 'sitesync', 'test=1');">Outdated files</a><br />
                View files pending synchronization
            </li>
            <li id="nav-sitesync">
                <a href="#" onclick="if (doSiteSync()) {openDialog(this.form, 'sitesync')};">Synchronize site</a><br />
                Push local changes to production site
            </li>
            <li id="nav-sitesync-log">
                <a href="$log_uri">Sync history</a><br />
                A log of previous sync operations
            </li>
        </ul>
    </div>
    </div>
EOD
    
    $$tmpl =~ s{$newsbox}{$replace}sm;
}

# Allows external access to plugin object: MT::Plugin::MyPlugin->instance
sub instance { $plugin }

sub runner {
    shift if ref($_[0]) eq ref($plugin);
    my $method = shift;
    $PLUGIN_MODULE = plugin_module();
    eval "require $PLUGIN_MODULE";
    if ($@) { print STDERR $@; $@ = undef; return 1; }
    my $method_ref = $PLUGIN_MODULE->can($method);
    return $method_ref->($plugin, @_) if $method_ref;
    my $logger = get_logger();
    $logger->logcroak($plugin->translate(
        'Failed to find '.$PLUGIN_MODULE.'::[_1]', $method));
}

sub sitesync {
    my $app = shift;
    my $logger = get_logger();
    $logger->marker();
    is_authorized($app)
        or return $app->error($app->translate("Permission denied."));

    my $cfg = $plugin->get_config_hash();

    $cfg->{rsync_options} ||= $plugin->settings->defaults()->{rsync_options};

    $| = 1;
    
    # Set up and commence app output
    $app->{no_print_body} = 1;
    $app->send_http_header;
    $app->print($app->build_page('header-dialog.tmpl'));

    if (   ! $cfg->{destination_path}
        or ! $cfg->{source_path} or ! -d $cfg->{source_path}) {

        my $dest = $cfg->{destination_path} || 'NOT SPECIFIED';
        my $src = $cfg->{source_path} ? $cfg->{source_path}.' (Not found)' 
                                      : 'NOT SPECIFIED';

        my $settings = $app->uri(mode => 'list_plugins');
        $app->print(dialog_header('ERROR', 'Incorrect SiteSync settings'));
        $app->print('<p>Your SiteSync settings are incorrect:</p>');
        $app->print(sprintf(
            '<ul><li>Source: %s</li><li>Destination: %s</li></ul>',
            $src, $dest));
        $app->print('<p>Please check both the source path and destination '
                    .'path in the <a href="'.$settings
                    .'" target="_blank">plugin ' 
                    .'configuration</a> and try again.</p>');
        $app->print(dialog_footer($app->uri(mode => 'list_blogs')));
    }
    else {
        _do_sync($app, $cfg);
    }

    $app->print($app->build_page('footer-dialog.tmpl'));
}

sub _do_sync {
    my ($app, $cfg) = @_;
    my $logger = get_logger();
    $logger->marker();
    
    my $user = $app->user;
    my ($username, $user_id) = ($user->name, $user->id);

    my $cmd;
    if ($cfg->{rsync_command}) {
        $cmd = $cfg->{rsync_command};        
        $cmd =~ s!rsync!rsync -n! if $app->param('test');
    }
    else {
        
        # Set up rsync command
        $app->param('test')     and $cfg->{rsync_options} .= ' -n';
        $cfg->{delete_orphans}  and $cfg->{rsync_options} .= ' --delete';
        if ($cfg->{remote_user}) {
            $cfg->{remote_server} ||= 'localhost';
            $cfg->{destination_path}
                = $cfg->{remote_user}.'@'. $cfg->{remote_server}.
                ':'. $cfg->{destination_path};
            $cfg->{rsync_options} = '-e ssh '.$cfg->{rsync_options};
        }

        $cmd = sprintf("rsync %s \"%s\" \"%s\"", 
                        $cfg->{rsync_options}, $cfg->{source_path},
                        $cfg->{destination_path});    
    }

    my $title = $app->param('test') ? "Outdated files"
                                    : "Synchronizing site";
    my $subtitle = join(' to ', $cfg->{source_path}, $cfg->{destination_path});


    # Begin output
    $app->print(dialog_header($title, $subtitle));

    if ($app->param('test')) {
        my $last_sync = last_sync();
        $app->print(sprintf(
            '<div style="background-color: #ff9; padding: 5px; margin-right: 20px"><p><em>The following is a list of files that either need to be updated or, where specified, deleted in order to synchronize the source and destination locations.</p><p>The last successful sync was performed on %s by %s</em></p></div>', $last_sync->{ts_str}, $last_sync->{user_str}));
    }

    # Command execution and output
    my $test_file_count;
    my $start = [gettimeofday];
    my @yo = (`$cmd  2>&1`);

    if ($app->param('test')) {
        # Strip unnecessary lines
        @yo = grep {
                ! m{(bytes received|bytes/sec|total\ssize\sis)}
            and ! m{^$}
            } @yo;
        # Only one ("Building file list...") means nothing out of sync
        if (@yo == 1) {
            $app->print($plugin->translate_templatized(
                '<p><strong>No outdated files exist on '
                .$cfg->{destination_path}
                .'</strong></p>'));
        }
        else {
            _progress($app, $_) foreach @yo;
            $test_file_count = 
                sprintf('&nbsp;&nbsp;&nbsp;<strong>Outdated files found: %s.  <a href="%s">Synchronize your site now</a></strong>', 
                (@yo - 1), $app->uri(mode => 'sitesync'));
        }
    }
    else {
        # $app->print(sprintf(
        #     '<div style="background-color: #99f; padding: 5px; margin-right: 20px"><p><strong>Command:</strong> %s</p></div>', $cmd));

        _progress($app, $_) foreach @yo;
    }


    # Handle logging and error conditions
    my $exit = $? >> 8;
    if ($exit != 0) {
        # TBD: notification to administrator
        # At the very least, log to MT activity log.
        my $err = 'Error during rsync of files...<br />'
                    ."\nCommand: $cmd\n";
        $app->print($plugin->translate_templatized(qq{<p class="error-message"><MT_TRANS phrase="Error">: $err</p>}));

        $app->log({
            message => sprintf("Site Sync: Synchronization failed for "
                        ."user '%s' (ID:%s)'", $username, $user_id),
            level => MT::Log::ERROR(),
            category => 'sitesync',
            metadata => "Command: $cmd\nOutput: ".join("\n", @yo),
        });

    }
    else {

        my $finis = sprintf("Finished! (%0.02fs)$test_file_count\n",
                    tv_interval($start));

        my $return_uri = $app->uri(mode => 'list_blogs');

        $app->print(dialog_footer($return_uri, $finis));

        unless ($app->param('test')) {
            my @ts = gmtime(time);
            my $ts = sprintf '%04d%02d%02d%02d%02d%02d',
                $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];

            $plugin->set_config_value('last_sync_time', $ts);
            $plugin->set_config_value('last_sync_user', $user_id);
            $app->log({
                message => sprintf("Site Sync: Synchronization succssfully ".
                            "completed by user '%s' (ID:%s).",
                            $username, $user_id),
                level => MT::Log::INFO(),
                category => 'sitesync',
                metadata => "Command: $cmd\nTransferred:\n".join("\n", @yo),
            });

        }
    }
    
}


sub last_sync {
    my $logger = get_logger();
    $logger->marker();
    my $ts      = $plugin->get_config_value('last_sync_time') or return;
    my $user_id = $plugin->get_config_value('last_sync_user');
    my $user    = MT::Author->load($user_id);
    require MT::Util;
    {
        user => $user,
        user_str => sprintf("%s (ID: %s)", $user->name, $user_id),
        ts => $ts,
        ts_str => MT::Util::format_ts("%Y.%m.%d %H:%M:%S", $ts),
    }
}


sub is_authorized {
    my $app = shift;
    my $logger = get_logger();
    $logger->marker();
    
    if(my $user = $app->user) {

        my $cfg = $plugin->get_config_hash();

        return 1 if $user->is_superuser or $cfg->{authorized_users} eq 'all';

        if ($cfg->{authorized_users} eq 'blogadmin') {
            my $iter = MT::Blog->load_iter();
            while (my $blog = $iter->()) {
                next unless $user->permissions($blog->id)->can_administer_blog;
                return 1;
            }
        }
        elsif ($cfg->{authorized_users} eq 'selected') {
            my $username = $user->name;
            my @authorized = split(/\s*,\s*/, ($cfg->{authorized_usernames}||''));
            return 1 if grep { /$username/ } @authorized;
        }
    }
}

sub dialog_header {
    my $title = shift || 'Untitled';
    my $subtitle = shift || '';
    my $logger = get_logger();
    $logger->marker();

    $title .= ': ' if $subtitle;

    my $out = $plugin->translate_templatized(<<"HTML");
    <script type="text/javascript">
    function progress(str, id) {
        var el = getByID(id);
        if (el) el.innerHTML = str;
    }
    </script>

    <div class="modal_width dialog" id="dialog-sitesync">
    <div id="cloning-panel" class="panel">
    <h2><span class="weblog-title-highlight">$title</span> $subtitle</h2>
    <div class="list-data-wrapper list-data">
    <ul>
HTML
    $out;
}

sub dialog_footer {
    my $return_uri = shift;
    my $summary = shift || '';
    my $logger = get_logger();
    $logger->marker();
    
    my $out = $plugin->translate_templatized(<<"HTML");
    </ul>
    </div>
    <div><p class="page-desc">$summary</p></div>
    <div class="panel-commands">
    <input type="button" value="<MT_TRANS phrase="Close">" onclick="closeDialog()" />
    </div>
    </div>
    </div>
HTML
    $out;
}

sub _progress {
    my $app = shift;
    my $ids = $app->request('progress_ids') || {};

    my ($str, $id) = @_;
    if ($id && $ids->{$id}) {
        require MT::Util;
        my $str_js = MT::Util::encode_js($str);
        $app->print(qq{<script type="text/javascript">progress('$str_js', '$id');</script>\n});
    } elsif ($id) {
        $ids->{$id} = 1;
        $app->print(qq{<li id="$id">$str</li>\n});
    } else {
        $app->print("<li>$str</li>");
    }

    $app->request('progress_ids', $ids);
}



1;
