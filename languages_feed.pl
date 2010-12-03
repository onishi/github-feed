#!/usr/bin/env perl
use strict;
use warnings;

use URI;
use Web::Scraper;
use XML::Feed;
use DateTime::Format::DateParse;
use URI::Escape 'uri_escape';

my $language = shift || 'Perl';
my $type     = shift || 'updated';
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
    process 'div.gravatar img',           'gravatar'       => '@src';
};

create_feed($language, $type);

exit(0);

sub create_feed {
    my ($language, $type) = @_;
    my $uri = URI->new(sprintf $lang_uri, uri_escape($language), $type);
    my $res = $list_scraper->scrape($uri);
    my $feed = XML::Feed->new('RSS', version => 2.0);
    $feed->title(sprintf 'Recently %s %s Repositories - GitHub', ucfirst $type, ucfirst $language);
    $feed->link($uri);
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
           $entry->content(make_content($repo, $info));
        $feed->add_entry($entry);
    }
    print $feed->as_xml;
}

sub repo_info {
    my ($author, $project) = @_;
    return $cache->{repo_info}->{$author}->{$project} ||= $repo_scraper->scrape(
        URI->new(sprintf $repo_uri, $author, $project)
    );
}

sub make_content {
    my ($repo, $info) = @_;
    my $content = '';
    $content .= sprintf '<img src="%s" alt="" width="30" height="30" align="left" />', $info->{gravatar} if $info->{gravatar};
    $content .= sprintf '<pre>%s</pre>', $info->{commit_message} if $info->{commit_message};
    $content .= '<br clear="all" />';
    $content .= $info->{readme} || $info->{description} || '';
    $content .= sprintf '<input value="git clone git://github.com/%s/%s.git" style="width: 60em" readonly="readonly" />', $repo->{author}, $repo->{project};
    $content;
}


__END__

=head1 NAME

languages_feed.pl

=head1 SYNOPSIS

  % perl languages_feed.pl perl updated
  % perl languages_feed.pl scala created

=head1 DESCRIPTION

make github languages rss feed

=head1 AUTHOR

Yasuhiro Onishi E<lt>yasuhiro.onishi@gmail.comE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
