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
use Book::Index::Splitter;
use Lingua::Stem::Snowball;
use Roman;

has 'doc'                 => ( is => 'rw' );
has 'doc_contents'        => ( is => 'rw' );
has 'phrase_doc'          => ( is => 'rw' );
has 'phrase_doc_contents' => ( is => 'rw' );
has 'verbose'             => ( is => 'rw', isa => 'Bool' );
has 'splitter'            => ( is => 'ro', builder => sub { Book::Index::Splitter->new } );
has 'stemmer'             => ( is => 'ro', builder => sub { Lingua::Stem::Snowball->new( lang => 'en' ) } );
has 'seen_phrases' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );    # not needed?
has 'seen_words' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'seen_stems' => ( is => 'rw', isa => 'HashRef', default => sub { +{} } );
has 'log_indent' => ( is => 'rw', isa => 'Int',     default => 0 );
has 'max_pages'   => ( is => 'rw', 'isa' => 'Int', default => 20 );
has 'max_phrases' => ( is => 'rw', 'isa' => 'Int', default => 0 );
has 'pre_pages' => ( is => 'rw', 'isa' => 'Int', default => 0 );

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

            $phrase =~ s/^\s+|\s+$//g;
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
    my @words = $self->splitter->words( $page->contents );
    $self->log( 'Page ' . $page->page . ': ' . scalar @words . ' new words' );

    my ( %word_freq, %stem_freq );
    for my $word (@words) {

        # Get canonical word and stem
        $word = lc $word;
        my $stem = lc $self->stemmer->stem($word) || '';

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
    my @words = $self->splitter->words( $phrase->original );

    # $self->log("PHRASE WORDS: " . join ':', @words);

    $self->populate_phrase_words( $phrase, @words );
    $self->populate_phrase_stems( $phrase, @words );

}

sub populate_phrase_words {
    my ( $self, $phrase, @words ) = @_;

    # Skip if word not in words table
    my $words = join ', ', map { Book::Index->dbh->quote( lc $_ ) } @words;
    my @phrase_words = Book::Index::Word->select("where word in ( $words )");

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

    # Skip if stem not in stems table
    my $stems = join ', ', map { Book::Index->dbh->quote( lc $_ ) } @phrase_stems;
    @phrase_stems = Book::Index::Stem->select("where stem in ( $stems )");
    
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
            my $n = $hay =~ s/\b$needle\b//ig;
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

sub format_page {
    my ( $self, $page ) = @_;
    $page = $page->page if ref $page;
    return $page <= $self->pre_pages ? lc Roman($page) : $page - $self->pre_pages;
}

sub output1 {
    my $self = shift;

    my %pages;
    for my $page ( Book::Index::Page->select ) {
        $page = $page->page;

        # Make sure page entry exists
        $pages{$page} = {};

        # Mush together phrases, words and stems
        my %shown_on_page;
        for my $phrase_page ( Book::Index::PhrasePage->select( 'where page = ?', $page ) ) {
            my $phrase = Book::Index::Phrase->load( $phrase_page->phrase );
            my $n      = $phrase_page->n;
            push @{ $pages{$page}{phrases} },
                $phrase->original . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
            $shown_on_page{ $phrase->phrase }++;
        }

        # Words for phrase on page
        for my $phrase_word_page ( Book::Index::PhraseWordPage->select( 'where page = ?', $page ) ) {
            my $word   = Book::Index::Word->load( $phrase_word_page->word );
            my $phrase = Book::Index::Phrase->load( $phrase_word_page->phrase );

            # Filter out words that match a phrase already output
            next if $shown_on_page{ $word->word }++;

            my $n = $phrase_word_page->n;
            push @{ $pages{$page}{words} },
                "@{[$word->word]} (@{[$phrase->original]})" . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
        }

        # Stems for phrase on page
        for my $phrase_stem_page ( Book::Index::PhraseStemPage->select( 'where page = ?', $page ) ) {
            my $stem   = Book::Index::Stem->load( $phrase_stem_page->stem );
            my $phrase = Book::Index::Phrase->load( $phrase_stem_page->phrase );

            # filter out stems that match a phrase already output
            next if $shown_on_page{ $stem->stem }++;

            my $n = $phrase_stem_page->n;
            push @{ $pages{$page}{stems} },
                "@{[$stem->stem]} (@{[$phrase->original]})" . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
        }
    }

    for my $page ( sort { $a <=> $b } keys %pages ) {
        say "-- Page @{[$self->format_page($page)]} --";
        say '';

        say 'Phrases:';
        if ( my @phrases = @{ $pages{$page}{phrases} || [] } ) {
            say join "\n", map {" $_ "} sort @phrases;
        }
        say '';

        if ( my @words = @{ $pages{$page}{words} || [] } ) {
            say 'Phrase Words:';
            say join "\n", map {" $_ "} sort @words;
            say '';
        }

        if ( my @stems = @{ $pages{$page}{stems} || [] } ) {
            say 'Phrase Stems:';
            say join "\n", map {" $_ "} sort @{ $pages{$page}{stems} || [] };
            say '';
        }
    }
}
    

sub output2 {
    my $self = shift;

    # Mush together phrase, word and stem to reduce redundancy
    my %shown;
    
    say "[Phrases]";
    for my $phrase ( Book::Index::Phrase->select('order by phrase') ) {
        my @pages;
        for my $phrase_page ( Book::Index::PhrasePage->select( 'where phrase = ?', $phrase->id ) ) {
            push @pages, $phrase_page->page;
        }
        say "@{[$phrase->original]}@{[$self->primary($phrase)]}: " . join ',', @pages;
        $shown{ $phrase->phrase }++;
    }
    say '';

    say "[Phrase Words]";
    {
        my @output;
        for my $phrase_word ( Book::Index::PhraseWord->select ) {
            my $phrase = Book::Index::Phrase->load( $phrase_word->phrase );
            my $word   = Book::Index::Word->load( $phrase_word->word );

            # Filter out any WORD that matches a phrase already output
            next if $shown{$word->word}++;

            my @pages;
            for my $phrase_word_page (
                Book::Index::PhraseWordPage->select( 'where phrase = ? and word = ?', $phrase->id, $word->id ) )
            {
                push @pages, $phrase_word_page->page;
            }
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

            # Filter out any STEM that matches a phrase already output
            next if $shown{$stem->stem}++;
            
            # Filter out stems that are stopwords
            next if $self->splitter->stop($stem->stem);

            my @pages;
            for my $phrase_stem_page (
                Book::Index::PhraseStemPage->select( 'where phrase = ? and stem = ?', $phrase->id, $stem->id ) )
            {
                push @pages, $phrase_stem_page->page;
            }
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

sub suggest_words {
    my $self = shift;

    my $sql = <<END_SQL;
where word not in ( select phrase from phrase )
  and id not in ( select word from phrase_word )
  and id not in ( select stem from phrase_stem )
END_SQL
    my %count;
    for my $word ( Book::Index::Word->select($sql) ) {
        next if $self->splitter->stop( $word->word );

        my @row = Book::Index->selectrow_array( 'select sum(n) from word_page where word = ?', undef, $word->id );
        $count{ $word->word } = $row[0];
    }
    my @top = sort { $count{$b} <=> $count{$a} or $a cmp $b } keys %count;
    say "Most common words:";
    for ( 0 .. 10 ) {
        my $word  = $top[$_];
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
    for my $stem ( Book::Index::Stem->select($sql) ) {
        next if $self->splitter->stop( $stem->stem );

        my @row = Book::Index->selectrow_array( 'select sum(n) from stem_page where stem = ?', undef, $stem->id );
        $count{ $stem->stem } = $row[0];
    }
    my @top = sort { $count{$b} <=> $count{$a} or $a cmp $b } keys %count;
    say "Most common stems:";
    for ( 0 .. 10 ) {
        my $stem  = $top[$_];
        my $count = $count{$stem};
        say " $stem ($count times)";
    }
    say '';
}

1;
