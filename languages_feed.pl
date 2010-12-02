#!/usr/bin/env perl
use strict;
use warnings;

use URI;
use Web::Scraper;
use XML::Feed;
use DateTime::Format::DateParse;
use IO::All;
use URI::Escape 'uri_escape';

my $language = shift || 'Perl';
my $lang_uri = 'https://github.com/languages/%s/%s'; # lang, type
my $repo_uri = 'https://github.com/%s/%s'; # author, project
my $cache;

my $list_scraper = scraper {
    process '//table[@class="repo"]/tr', 'repos[]' => scraper {
        process '//td[@class="title"]/a[1]', 'author'  => 'TEXT';
        process '//td[@class="title"]/a[2]', 'project' => 'TEXT';
    };
};

my $repo_scraper = scraper {
    process 'div.message pre a',          'commit_message' => 'TEXT';
    process 'div.date abbr',              'modified'       => 'TEXT';
    process 'div#repository_description', 'description'    => 'TEXT';
    process 'div#readme',                 'readme'         => sub { $_->as_HTML };
};

create_feed($language, $_) for qw(created updated);

exit;

sub create_feed {
    my ($language, $type) = @_;
    my $uri = URI->new(sprintf $lang_uri, uri_escape($language), $type);
    my $res = $list_scraper->scrape($uri);
    my $feed = XML::Feed->new('RSS', version => 2.0);
    $feed->title(sprintf 'Recent Github %s %s', ucfirst $language, ucfirst $type);
    for my $repo (@{$res->{repos} || []}) {
        my $author  = $repo->{author} or next;
        my $project = $repo->{project} or next;
        my $info    = repo_info($author, $project);
        my $entry = XML::Feed::Entry->new('RSS');
           $entry->title(sprintf '%s / %s', $repo->{author}, $repo->{project});
           $entry->link(sprintf $repo_uri, $repo->{author}, $repo->{project});
           $entry->author($repo->{author});
           $entry->issued(DateTime::Format::DateParse->parse_datetime($info->{modified}));
           $entry->summary($repo->{description}) if $repo->{description};
           $entry->content(make_content($info));
        $feed->add_entry($entry);
    }
    $feed->as_xml > io(sprintf '%s.%s.xml', uri_escape(lc $language), $type);
}

sub repo_info {
    my ($author, $project) = @_;
    return $cache->{repo_info}->{$author}->{$project} ||= $repo_scraper->scrape(
        URI->new(sprintf $repo_uri, $author, $project)
    );
}

sub make_content {
    my $repo = shift or return;
    my $content = '';
    $content .= sprintf '<blockquote>%s</blockquote>', $repo->{commit_message} if $repo->{commit_message};
    $content .= $repo->{readme} || $repo->{description} || '';
    $content;
}
