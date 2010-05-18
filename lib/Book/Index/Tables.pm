package Book::Index::Tables;

# ABSTRACT: Defines ORLite tables

sub USER_VERSION() {1}

sub create {
    my $dbh = shift;

    $dbh->do( 'PRAGMA user_version = ' . USER_VERSION );

    my %schema = (

        # each page of the doc
        page => [qw(page contents)],

        # the phrases that we care about for the final index
        # parse the phrase list
        #  split each line into multiple phrases via ';'
        #  first phrase in line is the primary phrase
        # iterate over each phrase
        #  phrase is lower-case
        #  original is unmodified non lower-case
        #  primary_id is id of first phrase on line
        phrase => [qw(phrase original primary)],

        # all words in document
        # iterate over pages
        #  use splitter to separate words
        #  use stemmer to compute stem
        word => [qw(word stem)],

        # stems of all words in document
        # populate while iterating over pages for words table
        stem => [qw(stem)],

        # each page that each word appears on
        # populate while iterating over pages for words table
        word_page => [qw(word page n)],

        # each page that each stem appears on
        # iterate over stems, add page row with times combined for any words that map to this stem for each page
        stem_page => [qw(stem page n)],

        # each page that each phrase appears on
        # iterate over pages
        #  iterate over phrases
        #   regex search through page contents
        phrase_page => [qw(phrase page n)],

        # iterate over phrases
        #  use splitter to get words from phrase
        #   being-attuned becomes two words
        #   Wood, David becomes two words
        #  skip if word not in words table
        #  multiple rows for word common to multiple phrases
        phrase_word => [qw(phrase word)],

        # iterate over phrases
        #  use splitter to get words from phrase
        #  skip phrase words that start with a capital letter (authors etc..)
        #  use stemmer to get stems from words
        #  skip if stem not in stems table
        #  multiple rows for stem common to multiple words
        phrase_stem => [qw(phrase stem)],

        # iterate over phrase_words
        #  add all word_pages matches
        #  multiple rows for word common to multiple phrases (so don't sum times)
        phrase_word_page => [qw(phrase word page n)],

        # iterate over phrase_stems
        #  add all stem_pages matches
        #  multiple rows for stem common to multiple words (so don't sum times)
        phrase_stem_page => [qw(phrase stem page n)],
    );

    for my $table ( sort keys %schema ) {
        my $cols = join ",\n    ", map {"`$_`"} @{ $schema{$table} };
        my $sql = <<END_SQL;
CREATE TABLE `$table` (
    id INTEGER PRIMARY KEY,
    $cols
)
END_SQL

        # warn $sql;
        $dbh->do($sql);
    }
}

use ORLite {
    'package'    => 'Book::Index',
    file         => 'sqlite.db',
    user_version => USER_VERSION,

    #cleanup      => 'VACUUM',
    create => \&create,

    # prune  => 1,          # while developing
};

1;
