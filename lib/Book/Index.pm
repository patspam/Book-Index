package Book::Index;

# ABSTRACT: Create an index for a book manuscript

=head1 SYNOPSIS

 # Perform frequency analysis on doc
 book_index --doc text.txt --max-pages 3 -v
 
 # Analyse doc using user-supplied phrase list
 book_index --phrases phrases.txt -v
 
 # Generate report
 book_index --report --pre-pages 14 > report.html
 
 # Suggest words to add to phrase list
 book_index --suggest
 
 # Combined (so you can walk away and have a coffee)
 book_index --doc text.txt --phrases phrases.txt --report --pre-pages 14 > report.html && book_index --suggest
 
=head1 STYLING

You can create a file called style.css in the same directory as the generated HTML report
to skin your report.
 
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
use HTML::Entities qw();
use Encode;
sub encode_entities { HTML::Entities::encode_entities( decode("utf8", $_[0]) ) }

has 'doc'                 => ( is => 'rw' );
has 'doc_contents'        => ( is => 'rw' );
has 'phrase_doc'          => ( is => 'rw' );
has 'phrase_doc_contents' => ( is => 'rw' );
has 'verbose'             => ( is => 'rw', isa => 'Bool' );
has 'splitter'            => ( is => 'ro', builder => sub { Book::Index::Splitter->new } );
has 'stemmer'             => ( is => 'ro', builder => sub { Lingua::Stem::Snowball->new( lang => 'en' ) } );
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

sub build_doc_information {
    my $self = shift;

    die "File not found: @{[$self->doc]}"        unless -e $self->doc;
    $self->slurp_doc;
    
    # Clear all tables that we want to build from scratch
    for my $table qw(Page Word Stem WordPage StemPage)
    {
        my $class = "Book::Index::$table";
        $class->truncate;
    }
    $self->populate_pages;
}

sub build_phrase_information {
    my $self = shift;

    die "File not found: @{[$self->phrase_doc]}" unless -e $self->phrase_doc;
    $self->slurp_phrase_doc;
    
    # Clear all tables that we want to build from scratch
    for my $table qw(Phrase PhrasePage PhraseWord PhraseStem PhraseWordPage PhraseStemPage)
    {
        my $class = "Book::Index::$table";
        $class->truncate;
    }
    $self->populate_phrases;
    $self->populate_phrase_pages;    # iterates over pages and phrases
}

sub report {
    my $self = shift;
    
    binmode(STDOUT, ":utf8");
    say <<'END_HTML';
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="en">
  <head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8">
    <title>Book Index</title>
    <link rel="stylesheet" type="text/css" href="style.css">
  </head>
  <body>
END_HTML
    $self->report1;
    $self->report2;
    say '</body></html>';
}

sub populate_pages {
    my $self     = shift;
    my $contents = $self->doc_contents;

    # Private object caches, shared across all pages
    my ( %seen_words, %seen_stems );
        
    $self->log('Populating pages->');
    my $page_counter = 0;
    for my $page_contents ( split "\f", $contents ) {
        $page_counter++;
        
        my $page = Book::Index::Page->new(
            page     => $page_counter,
            contents => $page_contents,
        )->insert;
        
        $self->process_page($page, \%seen_words, \%seen_stems);

        last if $self->max_pages && $page_counter >= $self->max_pages;
    }
    $self->log("<-Inserted $page_counter pages");
}

sub populate_phrases {
    my $self     = shift;
    my $contents = $self->phrase_doc_contents;

    # Private cache
    my %seen_phrases;
    
    $self->log('Populating phrases->');
    my $phrase_line_counter = 0;
    my $phrase_counter = 0;
    for my $phrase_line ( split "\n", $contents ) {
        $phrase_line_counter++;

        # $self->log("LINE: $phrase_line->");
        my $primary_id;
        for my $phrase ( split /;/, $phrase_line ) {

            $phrase =~ s/^\s+|\s+$//g;
            next unless length $phrase > 0;

            # No need to populate phrases twice
            if ( $seen_phrases{$phrase}++ ) {
                warn "Duplicate phrase: $phrase, line $phrase_line_counter";
                next;
            }

            $phrase_counter++;
            $self->log("Processed $phrase_counter phrases") if $phrase_counter % 10 == 0;

            # $self->log("PHRASE: $phrase->");
            my $new_phrase = Book::Index::Phrase->new(
                phrase   => lc $phrase,
                original => $phrase,
                primary  => $primary_id,    # null for first on line
            )->insert;

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
    my ( $self, $page, $seen_words, $seen_stems ) = @_;
    
    # Count word and stem appearances on this page
    my ( %word_freq, %stem_freq );

    # Get words on page
    my @words = $self->splitter->words( $page->contents );
    $self->log( 'Page ' . $page->page . ': ' . scalar @words . ' new words' );

    for my $word (@words) {

        # Get canonical word and stem
        $word = lc $word;
        my $stem = lc $self->stemmer->stem($word) || '';

        # Insert word and stem into db (if not found in private cache)
        $seen_stems->{$stem} ||= Book::Index::Stem->new( stem => $stem )->insert;
        $seen_words->{$word} ||= Book::Index::Word->new( word => $word, stem => $seen_stems->{$stem}->id )->insert;

        # Bump the counts
        $stem_freq{$seen_stems->{$stem}->id}++;
        $word_freq{$seen_words->{$word}->id}++;
    }

    # Create word_page and stem_page entries
    for my $word_id ( keys %word_freq ) {
        Book::Index::WordPage->new(
            word => $word_id,
            page => $page->page,
            n    => $word_freq{$word_id}
        )->insert;
    }
    for my $stem_id ( keys %stem_freq ) {
        Book::Index::StemPage->new(
            stem => $stem_id,
            page => $page->page,
            n    => $stem_freq{$stem_id}
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
        return ' [<i>' . encode_entities(Book::Index::Phrase->load( $phrase->primary )->phrase) . '</i>]';
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

sub report1 {
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
                "<b>@{[encode_entities($phrase->original)]}</b>" . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
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
                "<b>@{[encode_entities($word->word)]}</b> (@{[encode_entities($phrase->original)]})" . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
        }

        # Stems for phrase on page
        for my $phrase_stem_page ( Book::Index::PhraseStemPage->select( 'where page = ?', $page ) ) {
            my $stem   = Book::Index::Stem->load( $phrase_stem_page->stem );
            my $phrase = Book::Index::Phrase->load( $phrase_stem_page->phrase );

            # filter out stems that match a phrase already output
            next if $shown_on_page{ $stem->stem }++;

            my $n = $phrase_stem_page->n;
            push @{ $pages{$page}{stems} },
                "<b>@{[encode_entities($stem->stem)]}</b> (@{[encode_entities($phrase->original)]})" . ( $n > 1 ? " x $n" : '' ) . $self->primary($phrase);
        }
    }

    say '<h1 class=pages>Pages</h1>';
    for my $page ( sort { $a <=> $b } keys %pages ) {
        say "<div class=page><div class=page_header>--Page @{[$self->format_page($page)]} --</div>";

        if ( my @phrases = @{ $pages{$page}{phrases} || [] } ) {
            say '<div class=page_phrases><span class=page_phrases_label>Phrases:</span><span class=page_phrases>';
            say join "; ", map {" $_ "} sort @phrases;
            say '</span></div>';
        }

        if ( my @words = @{ $pages{$page}{words} || [] } ) {
            say '<div class=page_words><span class=page_words_label>Words:</span><span class=page_words>';
            say join "; ", map {" $_ "} sort @words;
            say '</span></div>';
        }

        if ( my @stems = @{ $pages{$page}{stems} || [] } ) {
            say '<div class=page_stems><span class=page_stems_label>Stems:</span><span class=page_stems>';
            say join "; ", map {" $_ "} sort @{ $pages{$page}{stems} || [] };
            say '</span></div>';
        }
        say '</div>';
    }
}
    

sub report2 {
    my $self = shift;

    # Mush together phrase, word and stem to reduce redundancy
    my %shown;
    
    say '<h1 class=index>Index</h1>';
    
    say "<h2 class=phrases>Phrases</h2>";
    say '<div class=index_phrases>';
    for my $phrase ( Book::Index::Phrase->select('order by phrase') ) {
        my @pages;
        for my $phrase_page ( Book::Index::PhrasePage->select( 'where phrase = ?', $phrase->id ) ) {
            push @pages, $self->format_page($phrase_page->page);
        }
        say encode_entities($phrase->original) . $self->primary($phrase) . ': ' . join ',', @pages;
        say '<br>';
        $shown{ $phrase->phrase }++;
    }
    say '</div>';

    say "<h2 class=phrase_words>Phrase Words</h2>";
    say '<div class=index_phrase_words>';
    {
        my @output;
        for my $phrase_word ( Book::Index::PhraseWord->select ) {
            my $phrase = Book::Index::Phrase->load( $phrase_word->phrase );
            my $word   = Book::Index::Word->load( $phrase_word->word );

            # Filter out any WORD that matches a phrase already output
            next if $shown{$word->word}++;
            next if $word->word eq '';

            my @pages;
            for my $phrase_word_page (
                Book::Index::PhraseWordPage->select( 'where phrase = ? and word = ?', $phrase->id, $word->id ) )
            {
                push @pages, $self->format_page($phrase_word_page->page);
            }
            push @output, '<span class=index_phrase_word>' . encode_entities($word->word) . '</span> (' . encode_entities($phrase->original) . ') ' . $self->primary($phrase) . ': ' . join ',', @pages;
        }
        say join "<br>", sort @output;
        say '';
    }
    say '</div>';

    say "<h2 class=phrase_stems>Phrase Stems</h2>";
    say '<div class=index_phrase_stems>';
    {
        my @output;
        for my $phrase_stem ( Book::Index::PhraseStem->select ) {
            my $phrase = Book::Index::Phrase->load( $phrase_stem->phrase );
            my $stem   = Book::Index::Stem->load( $phrase_stem->stem );

            # Filter out any STEM that matches a phrase already output
            next if $shown{$stem->stem}++;
            next if $stem->stem eq '';
            
            # Filter out stems that are stopwords
            next if $self->splitter->stop($stem->stem);

            my @pages;
            for my $phrase_stem_page (
                Book::Index::PhraseStemPage->select( 'where phrase = ? and stem = ?', $phrase->id, $stem->id ) )
            {
                push @pages, $self->format_page($phrase_stem_page->page);
            }
            push @output, '<span class=index_phrase_stem>' . encode_entities($stem->stem) . '</span> (' . encode_entities($phrase->original) . ') ' .$self->primary($phrase) . ': ' . join ',', @pages;
        }
        say join "<br ", sort @output;
    }
    say '</div>';
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
    for ( 0 .. 50 ) {
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
    for ( 0 .. 50 ) {
        my $stem  = $top[$_];
        my $count = $count{$stem};
        say " $stem ($count times)";
    }
    say '';
}

1;
