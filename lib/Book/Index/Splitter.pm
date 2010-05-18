package Book::Index::Splitter;
use Any::Moose;
use List::MoreUtils qw(uniq);
use Scalar::Util qw(looks_like_number);

has 'stop_words' => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    default => sub {
        return {
            map { lc $_ => 1 }
                qw(
                a b c d e f g h i j k l m n o p q r s t u v w x y z
                about above across adj after again against all almost alone along also
                although always am among an and another any anybody anyone anything anywhere
                apart are around as aside at away be because been before behind below
                besides between beyond both but by can cannot could deep did do does doing done
                down downwards during each either else enough etc even ever every everybody
                everyone except far few for forth from get gets got had hardly has have having
                her here herself him himself his how however i if in indeed instead into inward
                is it its itself just kept many maybe might mine more most mostly much must
                myself near neither next no nobody none nor not nothing nowhere of off often on
                only onto or other others ought our ours out outside over own p per please plus
                pp quite rather really said seem self selves several shall she should since so
                some somebody somewhat still such than that the their theirs them themselves
                then there therefore these they this thorough thoroughly those through thus to
                together too toward towards under until up upon v very was well were what
                whatever when whenever where whether which while who whom whose will with
                within without would yet young your yourself
                )
        };
    },
);

sub stop {
    my ( $self, $word ) = @_;
    warn "Got a ref" if ref $word;
    $word = lc $word;
    return 1         if $self->{stop_words}{$word};
    return 1         if looks_like_number($word);
    return;
}

sub words {
    my ( $self, $contents ) = @_;

    my @words = split /\W+/, $contents;
    @words = grep { !$self->stop($_) } @words;
    #return uniq @words;
    return uniq map { s/^\s+|\s+$//g; $_ } @words;
}

1;
