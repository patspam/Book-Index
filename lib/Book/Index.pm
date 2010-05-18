package Book::Index;

# ABSTRACT: Create an index for a book manuscript

=head1 DESCRIPTION

=cut

use 5.010;
use strict;
use warnings;

use Book::Index::Tables;
use Any::Moose;
use File::Slurp qw(read_file);
use Lingua::EN::Splitter;    # TODO: replace with something better (that doesn't convert to lc!)
use Lingua::Stem::Snowball;
use Lingua::EN::StopWords qw(%StopWords);
use List::MoreUtils qw(uniq);
use Scalar::Util qw(looks_like_number);

has 'doc'                 => ( is => 'rw' );
has 'doc_contents'        => ( is => 'rw' );
has 'phrase_doc'          => ( is => 'rw' );
has 'phrase_doc_contents' => ( is => 'rw' );
has 'verbose'             => ( is => 'rw', isa => 'Bool' );
has 'splitter'            => ( is => 'ro', builder => sub { Lingua::EN::Splitter->new } );
has 'stemmer'             => ( is => 'ro', builder => sub { Lingua::Stem::Snowball->new( lang => 'en' ) } );
has 'seen_phrases' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );    # not needed?
has 'seen_words' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'seen_stems' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'log_indent' => ( is => 'rw', isa => 'Int',     default => 0 );
has 'max_pages'   => ( is => 'rw', 'isa' => 'Int', default => 10 );
has 'max_phrases' => ( is => 'rw', 'isa' => 'Int', default => 0 );

sub truncate {
    for my $table
        qw(Page Phrase Word Stem WordPage StemPage PhrasePage PhraseWord PhraseStem PhraseWordPage PhraseStemPage)
    {
        my $class = "Book::Index::$table";
        $class->truncate;
    }
}

sub process {
    my ( $self, $doc, $phrase_doc ) = @_;

    die "File not found: $doc"        unless -e $doc;
    die "File not found: $phrase_doc" unless -e $phrase_doc;
    $self->doc($doc);
    $self->phrase_doc($phrase_doc);

    $self->process_doc;
    $self->process_phrase_doc;
    $self->populate_phrase_pages;    # iterates over pages and phrases
}

sub output {
    my $self = shift;
    $self->output1;
    $self->output2;
}

sub process_doc {
    my $self = shift;
    $self->slurp_doc;
    $self->populate_pages;
}

sub process_phrase_doc {
    my $self = shift;
    $self->slurp_phrase_doc;
    $self->populate_phrases;
}

sub populate_pages {
    my $self     = shift;
    my $contents = $self->doc_contents;

    $self->log('Populating pages->');
    my $page_counter = 0;
    for my $page_contents ( split "\f", $contents ) {
        $page_counter++;
        my $page = Book::Index::Page->new(
            page     => $page_counter,
            contents => $page_contents,
        )->insert;

        $self->process_page($page);

        last if $self->max_pages && $page_counter >= $self->max_pages;
    }
    $self->log("<-Inserted $page_counter pages");
}

sub populate_phrases {
    my $self     = shift;
    my $contents = $self->phrase_doc_contents;

    $self->log('Populating phrases->');
    my $phrase_line_counter = 0;
    for my $phrase_line ( split "\n", $contents ) {
        $phrase_line_counter++;

        # $self->log("LINE: $phrase_line->");

        my $phrase_counter = 0;
        my $primary_id;
        for my $phrase ( split /;/, $phrase_line ) {

            $phrase =~ s/^\s+|\s+$//;
            next unless length $phrase > 0;

            # No need to populate phrases twice
            if ( $self->{seen_phrases}{$phrase} ) {
                warn "Duplicate phrase: $phrase, line $phrase_line_counter";
                next;
            }

            $phrase_counter++;

            # $self->log("PHRASE: $phrase->");

            my $new_phrase = $self->insert_phrase(
                phrase   => lc $phrase,
                original => $phrase,
                primary  => $primary_id,    # null for first on line
            );

            # First one becomes the primary id for all the others on the line
            $primary_id ||= $new_phrase->id;

            $self->process_phrase($new_phrase);

            # $self->log('<-');
            last if $self->max_phrases && $phrase_counter >= $self->max_phrases;
        }

        # $self->log('<-');
    }
}

sub process_page {
    my ( $self, $page ) = @_;

    # Get words on page
    my @words = uniq @{ $self->splitter->words( $page->contents ) };
    $self->log( 'Page ' . $page->page . ': ' . scalar @words . ' new words' );

    my ( %word_freq, %stem_freq );
    for my $word (@words) {

        # Get canonical word and stem
        $word = lc $word;    # TODO: do we really want lowercase?
        my $stem = $self->stemmer->stem($word) || '';

        # Insert word and stem into db
        my $new_stem = $self->insert_stem( stem => $stem );
        my $new_word = $self->insert_word( word => $word, stem => $new_stem->id );

        # Bump the counts
        $word_freq{$word}++;
        $stem_freq{$stem}++;
    }

    # Create word_page and stem_page entries
    for my $word ( keys %word_freq ) {
        Book::Index::WordPage->new(
            word => $self->{seen_words}{$word}->id,
            page => $page->page,
            n    => $word_freq{$word}
        )->insert;
    }
    for my $stem ( keys %stem_freq ) {
        Book::Index::StemPage->new(
            stem => $self->{seen_stems}{$stem}->id,
            page => $page->page,
            n    => $stem_freq{$stem}
        )->insert;
    }
}

sub process_phrase {
    my ( $self, $phrase ) = @_;

    # $self->log("PHRASE: " . $phrase->original);

    # Get words in phrase
    my @words = uniq @{ $self->splitter->words( $phrase->original ) };

    # $self->log("PHRASE WORDS: " . join ':', @words);

    $self->populate_phrase_words( $phrase, @words );
    $self->populate_phrase_stems( $phrase, @words );

}

sub populate_phrase_words {
    my ( $self, $phrase, @words ) = @_;

    # Skip if word not in words table
    my $seen_words = $self->seen_words;
    my @phrase_words = grep {$_} map { $seen_words->{$_} } @words;

    for my $word (@phrase_words) {

        # $self->log("NEW PHRASE WORD: " . $word->word);
        my $phrase_word = Book::Index::PhraseWord->new( phrase => $phrase->id, word => $word->id )->insert;

        # Add all word_pages matches
        for my $word_page ( Book::Index::WordPage->select( 'where word = ?', $word->id ) ) {

            # $self->log("WORD PAGE MATCH p" . $word_page->n . " " . $word->word);
            Book::Index::PhraseWordPage->new(
                phrase => $phrase->id,
                word   => $word->id,
                page   => $word_page->page,
                n      => $word_page->n,
            )->insert;
        }
    }
}

sub populate_phrase_stems {
    my ( $self, $phrase, @words ) = @_;

    # Skip phrase words that start with a capital letter (authors etc..)
    my @phrase_stems = grep { !m/^[A-Z]/ } @words;
    $self->stemmer->stem_in_place( \@phrase_stems );

    # $self->log("PHRASE STEMS: " . join ':', @phrase_stems);

    # Skip if stem not in stems table
    my $seen_stems = $self->seen_stems;
    @phrase_stems = grep {$_} map { $seen_stems->{$_} } @phrase_stems;
    for my $stem (@phrase_stems) {

        # $self->log("NEW PHRASE STEM: " . $stem->stem);
        Book::Index::PhraseStem->new( phrase => $phrase->id, stem => $stem->id )->insert;

        # Add all stem_pages matches
        for my $stem_page ( Book::Index::StemPage->select( 'where stem = ?', $stem->id ) ) {

            # $self->log("STEM PAGE MATCH p" . $stem_page->n . " " . $stem->stem);
            Book::Index::PhraseStemPage->new(
                phrase => $phrase->id,
                stem   => $stem->id,
                page   => $stem_page->page,
                n      => $stem_page->n,
            )->insert;
        }
    }
}

sub insert_phrase {
    my ( $self, %args ) = @_;
    my $original     = $args{original};       # use original instead of phrase
    my $seen_phrases = $self->seen_phrases;
    return $seen_phrases->{$original} = $seen_phrases->{$original} || Book::Index::Phrase->new(%args)->insert;
}

sub insert_word {
    my ( $self, %args ) = @_;
    my $word       = $args{word};
    my $seen_words = $self->seen_words;
    return $seen_words->{$word} = $seen_words->{$word} || Book::Index::Word->new(%args)->insert;
}

sub insert_stem {
    my ( $self, %args ) = @_;
    my $stem       = $args{stem};
    my $seen_stems = $self->seen_stems;
    return $seen_stems->{$stem} = $seen_stems->{$stem} || Book::Index::Stem->new(%args)->insert;
}

sub slurp_doc {
    my $self = shift;
    $self->log( "Reading doc: " . $self->doc );
    my $contents = read_file( $self->doc );
    $self->doc_contents($contents);
}

sub slurp_phrase_doc {
    my $self = shift;
    $self->log( "Reading phrase doc: " . $self->phrase_doc );
    my $contents = read_file( $self->phrase_doc );
    $self->phrase_doc_contents($contents);
}

sub log {
    my ( $self, $message ) = @_;
    $self->{log_indent}-- if $message =~ s/^<-//;
    $self->{log_indent}++ if $message =~ s/->$//;
    return unless $message;
    say( ( " " x $self->log_indent ) . $message ) if $self->verbose;
}

sub populate_phrase_pages {
    my $self = shift;

    for my $page ( Book::Index::Page->select ) {
        for my $phrase ( Book::Index::Phrase->select ) {
            my $p      = $page->page;
            my $needle = quotemeta $phrase->original;
            my $hay    = $page->contents;

            # $self->log("Checking p$p for: $needle");

            # Count matches on page
            my $n = $hay =~ s/$needle//ig;
            next unless $n;

            # $self->log("p$p MATCHED: $needle");
            Book::Index::PhrasePage->new(
                phrase => $phrase->id,
                page   => $p,
                n      => $n,
            )->insert;
        }
    }
}

sub primary {
    my ( $self, $phrase ) = @_;
    if ( $phrase->primary ) {
        return ' [' . Book::Index::Phrase->load( $phrase->primary )->phrase . ']';
    }
    else {
        return '';
    }
}

sub output1 {
    my $self = shift;

    my %pages;
    for my $page ( Book::Index::Page->select('order by page') ) {
        $page = $page->page;

        my %shown_on_page;
        Book::Index::PhrasePage->iterate(
            'where page = ?',
            $page,
            sub {
                my $phrase = Book::Index::Phrase->load( $_->phrase );
                my $n      = $_->n;
                push @{ $pages{$page}{phrases} },
                    $phrase->original . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
                $shown_on_page{ $phrase->original }++;
            }
        );

        # Words for phrase on page
        Book::Index::PhraseWordPage->iterate(
            'where page = ?',
            $page,
            sub {
                my $word   = Book::Index::Word->load( $_->word );
                my $phrase = Book::Index::Phrase->load( $_->phrase );

                # filter out words that match a phrase already output
                #return if $shown_on_page{$word->word};

                my $n = $_->n;
                push @{ $pages{$page}{words} },
                      "@{[$word->word]} (@{[$phrase->original]})"
                    . ( $n > 1 ? " x $n" : '' )
                    . $self->primary($phrase);
                $shown_on_page{ $word->word }++;
            }
        );

        # Stems for phrase on page
        Book::Index::PhraseStemPage->iterate(
            'where page = ?',
            $page,
            sub {
                my $stem   = Book::Index::Stem->load( $_->stem );
                my $phrase = Book::Index::Phrase->load( $_->phrase );

                # filter out stems that match a phrase already output
                #return if $shown_on_page{$stem->stem};

                my $n = $_->n;
                push @{ $pages{$page}{stems} },
                      "@{[$stem->stem]} (@{[$phrase->original]})"
                    . ( $n > 1 ? " x $n" : '' )
                    . $self->primary($phrase);
                $shown_on_page{ $stem->stem }++;
            }
        );
    }

    for my $page ( sort keys %pages ) {
        say "[Page $page]";
        say '';

        if ( my @phrases = @{ $pages{$page}{phrases} || [] } ) {
            say 'Phrases:';
            say join "\n", map {" $_ "} @phrases;
            say '';
        }

        if ( my @words = @{ $pages{$page}{words} || [] } ) {
            say 'Phrase Words:';
            say join "\n", map {" $_ "} @words;
            say '';
        }

        if ( my @stems = @{ $pages{$page}{stems} || [] } ) {
            say 'Phrase Stems:';
            say join "\n", map {" $_ "} @{ $pages{$page}{stems} || [] };
            say '';
        }
    }
}

sub output2 {
    my $self = shift;

    say "[Phrases]";
    my %shown;
    for my $phrase ( Book::Index::Phrase->select('order by phrase') ) {
        my @pages;
        Book::Index::PhrasePage->iterate(
            'where phrase = ?',
            $phrase->id,
            sub {
                push @pages, $_->page;
            }
        );
        say "@{[$phrase->original]}@{[$self->primary($phrase)]}: " . join ',', @pages;
        $shown{ $phrase->original }++;
    }
    say '';

    say "[Phrase Words]";
    {
        my @output;
        for my $phrase_word ( Book::Index::PhraseWord->select ) {
            my $phrase = Book::Index::Phrase->load( $phrase_word->phrase );
            my $word   = Book::Index::Word->load( $phrase_word->word );

            # filter out anything that matches a phrase already output
            # next if $shown{$phrase->original};

            # output phrase_word_pages as "$word ($original_phrase): 1,2,3,.."

            my @pages;
            Book::Index::PhraseWordPage->iterate(
                'where phrase = ? and word = ?',
                $phrase->id,
                $word->id,
                sub {
                    push @pages, $_->page;
                }
            );
            push @output, "@{[$word->word]} (@{[$phrase->original]})@{[$self->primary($phrase)]}: " . join ',',
                @pages;
        }
        say join "\n", sort @output;
        say '';
    }

    say "[Phrase Stems]";
    {
        my @output;
        for my $phrase_stem ( Book::Index::PhraseStem->select ) {
            my $phrase = Book::Index::Phrase->load( $phrase_stem->phrase );
            my $stem   = Book::Index::Stem->load( $phrase_stem->stem );

            # filter out anything that matches a phrase already output
            # next if $shown{$phrase->original};

            # output phrase_stem_pages as "$stem ($original_phrase): 1,2,3,.."

            my @pages;
            Book::Index::PhraseStemPage->iterate(
                'where phrase = ? and stem = ?',
                $phrase->id,
                $stem->id,
                sub {
                    push @pages, $_->page;
                }
            );
            push @output, "@{[$stem->stem]} (@{[$phrase->original]})@{[$self->primary($phrase)]}: " . join ',',
                @pages;
        }
        say join "\n", sort @output;
    }
}

sub suggest {
    my $self = shift;
    
    $self->suggest_words;
    $self->suggest_stems;
}

sub should_filter {
    my ($self, $word) = @_;
    warn "Got a ref" if ref $word;
    return 1 if $StopWords{$word};
    return 1 if looks_like_number($word);
    return;
}

sub suggest_words {
    my $self = shift;
    
    my $sql = <<END_SQL;
where word not in ( select phrase from phrase )
  and id not in ( select word from phrase_word )
  and id not in ( select stem from phrase_stem )
END_SQL
    my %count;
    for my $word (Book::Index::Word->select( $sql )) {
        next if $self->should_filter($word->word);
        
        my @row = Book::Index->selectrow_array('select sum(n) from word_page where word = ?', undef, $word->id);
        $count{$word->word} = $row[0];
    };
    my @top = sort { $count{$b} <=> $count{$a} or $a cmp $b } keys %count;
    say "Most common words:";
    for (0 .. 10) {
        my $word = $top[$_];
        my $count = $count{$word};
        say " $word ($count times)";
    }
    say '';
}

sub suggest_stems {
    my $self = shift;
    
    my $sql = <<END_SQL;
where stem not in ( select phrase from phrase )
  and id not in ( select word from phrase_word )
  and id not in ( select stem from phrase_stem )
END_SQL
    my %count;
    for my $stem (Book::Index::Stem->select( $sql )) {
        next if $self->should_filter($stem->stem);
        
        my @row = Book::Index->selectrow_array('select sum(n) from stem_page where stem = ?', undef, $stem->id);
        $count{$stem->stem} = $row[0];
    };
    my @top = sort { $count{$b} <=> $count{$a} or $a cmp $b } keys %count;
    say "Most common stems:";
    for (0 .. 10) {
        my $stem = $top[$_];
        my $count = $count{$stem};
        say " $stem ($count times)";
    }
    say '';
}

#
#
# sub process {
# my ( $class, $filename ) = @_;
#
# my @words =
# grep { !$StopWords{$_} }
# map  { lc } @{ $splitter->words( $pages[$page] ) };
#
# $stemmer->stem_in_place( \@words );
#
# my %freq;
# map { $freq{$_}++ } grep { !$StopWords{$_} } @words;
#
# for my $word ( keys %freq ) {
# Indexer::Word->new(
# word  => $word,
# count => $freq{$word},
# page  => $page
# )->insert;
# }
# }
#
# say "Finished procesing all pages.";
# }
#
# sub word {
# my ( $class, $word ) = @_;
# my $rows = Indexer->selectall_arrayref(
# 'select page, count from word where word = ?',
# undef, $word );
# print "$word: ";
# if ( !@$rows ) {
# say "not found.";
# return;
# }
# my @hits;
# for my $row (@$rows) {
# my $word = $row->[1];
# my $times = $row->[0];
# push @hits, $word . ( $times > 1 ? " (x$times)" : '' );
# }
# say join ', ', @hits;
# }
#
# sub top {
# my ( $class, $n ) = @_;
# $n ||= 10;
# my $rows = Indexer->selectall_arrayref(
# 'select sum(count) as count, word from word group by word order by count desc limit ?',
# undef, $n
# );
# say "Top $n Words:\n";
# for my $row (@$rows) {
# printf( "%5d %s\n", @$row );
# }
# }

1;
