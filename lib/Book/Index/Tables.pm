package Book::Index::Tables;

# ABSTRACT: Defines ORLite tables

sub USER_VERSION() {1}

sub create {
    my $dbh = shift;

    $dbh->do( 'PRAGMA user_version = ' . USER_VERSION );

    my %schema = (
        page             => [qw(page contents)],
        phrase           => [qw(phrase original primary)],
        stem             => [qw(stem)],
        word_page        => [qw(word page n)],
        phrase_page      => [qw(phrase word)],
        phrase_stem      => [qw(phrase stem)],
        phrase_word_page => [qw(phrase word page n)],
        phrase_stem_page => [qw(phrase stem page n)],
    );

    for my $table ( sort keys %schema ) {
        my $cols = join ",\n    ", map { "`$_`" } @{ $schema{$table} };
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
    file         => 'data/sqlite.db',
    user_version => USER_VERSION,
    #cleanup      => 'VACUUM',
    create       => \&create,
    prune        => 1,                  # while developing
};

1;
