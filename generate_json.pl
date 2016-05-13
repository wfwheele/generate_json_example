use strict;
use warnings;
use File::Slurp;
use Data::Dumper;
use feature qw/say/;
use Swagger2;
use JSON qw/encode_json/;
use Scalar::Util qw/looks_like_number/;
use String::Generator;
use Carp;

# if(scalar @ARGV != 1){
# 	say "\nUsage: generate_json.pl filename";
# 	exit;
# }

# my $swagger = Swagger2->new($ARGV[0]);
my $swagger = Swagger2->new('digication.yaml');
my $paths   = $swagger->api_spec->get('/paths');
my $str_gen = String::Generator->new();
my %subs    = (
    integer => sub {
        my $property = shift;
        my $pattern
            = exists $property->{pattern} ? $property->{pattern} : '\d+';
        my $value = $str_gen->generate($pattern);
        return numberify($value);
    },
    string => sub {
        my $property = shift;
        return dispatch_to( $property->{format}, $property )
            if exists $property->{format};
        my $pattern = exists $property->{pattern} ? $property->{pattern} : '.+';
        return $str_gen->generate($pattern);
    },
    number => sub {
        my $property = shift;
        return dispatch_to( $property->{format}, $property )
            if exists $property->{format};
        my $pattern
            = exists $property->{pattern}
            ? $property->{pattern}
            : '\d*(\.\d*)?';
        return $str_gen->generate($pattern);
    },
    date => sub {
        my $property = shift;
        return $str_gen->generate(
            '[1-2]\d{3}-(0[1-9]|1[0-2])-(0[1-9]|1[0-9]|2[0-9]|3[0-1])');
    },
    boolean => sub {
        my @options = ( \0, \1 );
        return $options[ rand(1) ];
    },
    object => sub {
        my $property = shift;
        my %object;
        for my $property_name ( keys %{ $property->{properties} } ) {
            my $prop = $property->{properties}->{$property_name};
            $prop = $swagger->api_spec->get( substr $prop->{'$ref'}, 1 )
                if exists $prop->{'$ref'};
            $object{$property_name}
                = dispatch_to( $prop->{type}, $prop );
        }
        return \%object;
    }
);

for my $path ( keys %{$paths} ) {
    if (    exists $paths->{$path}->{get}->{responses}->{200}->{schema}
        and exists $paths->{$path}->{get}->{responses}->{200}->{schema}->{type}
        and $paths->{$path}->{get}->{responses}->{200}->{schema}->{type} eq
        'array' )
    {
        my $schema  = $paths->{$path}->{get}->{responses}->{200}->{schema};
        my $item    = get_item($schema);
        my $str_gen = String::Generator->new();
				my @resources;
				for ( 0 .. 10000){
					push @resources, dispatch_to($item->{type}, $item);
				}
				write_to_file($schema->{title} . '.json', encode_json \@resources);
    }
}

sub dispatch_to {
    my $subname = shift;
    if ( exists $subs{$subname} ) {
        return $subs{$subname}->(@_);
    }
    else {
        confess "method $subname does not exist";
    }
}

sub numberify {
    my $scalar = shift;
    return $scalar *= 1;
}

sub get_item {
    my ($schema) = @_;
    if ( exists $schema->{items}->{'$ref'} ) {
        return $swagger->api_spec->get( substr $schema->{items}->{'$ref'}, 1 );
    }
    else {
        return $schema->{items};
    }
}

sub write_to_file {
    my ( $filename, $string ) = @_;
    open( my $fh, '>:encoding(UTF-8)', $filename )
        or die "Could not open file '$filename' $!";
    print $fh $string;
    close $fh;
    say "wrote to $filename";
}
