
package Lab::Moose::Instrument;
use 5.010;
use Moose;
use Moose::Util::TypeConstraints qw(enum duck_type);
use MooseX::Params::Validate;

use Data::Dumper;
use Exporter 'import';

our @EXPORT_OK = qw(
    timeout_param
    read_length_param
    channel_param
    precision_param
    getter_params
    setter_params
    validated_getter
    validated_setter
    validated_no_param_setter
    validated_channel_getter
    validated_channel_setter
);

# do not make imported functions available as methods.
use namespace::autoclean

    # Need this for Exporter.
    -except => 'import',
    -also   => [@EXPORT_OK];

our $VERSION = '3.520';

with 'Lab::Moose::Instrument::Log';

=head1 NAME

Lab::Moose::Instrument - Base class for instrument drivers.

=head1 SYNOPSIS

A complete device driver based on Lab::Moose::Instrument:

 package Lab::Moose::Instrument::FooBar;
 use Moose;
 
 use Lab::Moose::Instrument qw/validated_getter validated_setter/;

 use namespace::autoclean;
 
 extends 'Lab::Moose::Instrument';

 sub get_foo {
     my ($self, %args) = validated_getter(\@_);
     return $self->query(command => "Foo?", %args);
 }
 
 sub set_foo {
     my ($self, $value, %args) = validated_setter(\@_);
     return $self->write(command => "Foo $value", %args);
 }

 __PACKAGE__->meta->make_immutable();

=head1 DESCRIPTION

The Lab::Moose::Instrument module is a thin wrapper around a connection object.
All other Lab::Moose::Instrument::* drivers inherit from this module.

=head1 METHODS

=head2 new

See SYNOPSIS.
The constructor requires a connection object, which has
Read, Write, Query and Clear methods. You can provide any object, which
supports these methods.

=cut

has 'connection' => (
    is       => 'ro',
    isa      => duck_type( [qw/Write Read Query Clear/] ),
    required => 1
);

#
# Methods
#

my %command = ( command => { isa => 'Str' } );

=head2 write

 $instrument->write(command => '*RST', timeout => 10);

Call the connection's C<Write> method. The timeout parameter is optional.

=cut

sub write {
    my ( $self, %args ) = validated_hash( \@_, %command, setter_params(), );

    return $self->connection()->Write(%args);
}

=head2 read

 $instrument->read(timeout => 10, read_length => 10000);

Call the connection's C<Read> method. The timeout and read_length
parameters are optional.

=cut

sub read {
    my ( $self, %args ) = validated_hash( \@_, getter_params() );

    return $self->connection()->Read(%args);
}

=head2 query

 $instrument->query(command => '*IDN?', read_length => 10000, timeout => 10);

Call the connection's C<Query> method. The timeout and read_length parameters
are optional.

=cut

sub query {
    my ( $self, %args ) = validated_hash( \@_, %command, getter_params() );

    return $self->connection()->Query(%args);
}

=head2 clear

 $instrument->clear();

Call the connection's C<Clear> method.

=cut

sub clear {
    my $self = shift;
    $self->connection()->Clear();
}

=head1 Functions

The following functions standardise and simplify the use of
L<MooseX::Params::Validate> in instrument drivers. They are only exported on
request.

=head2 timeout_param

Return mandatory validation parameter for timeout.

=cut

sub timeout_param {
    return ( timeout => { isa => 'Num', optional => 1 } );
}

=head2 read_length_param

Return mandatory validation parameter for read_length.

=cut

sub read_length_param {
    return ( read_length => { isa => 'Int', optional => 1 } );
}

=head2 channel_param

Return optional validation parameter for channel. A given argument has to be an
'Int'. The default value is the empty string ''.

=cut

sub channel_param {
    return ( channel => { isa => 'Int', optional => 1 } );
}

=head2 precision_param

Return optional validation parameter for floating point precision. The
parameter has to be either 'single' (default) or 'double'.

=cut

sub precision_param {
    return ( precision =>
            { isa => enum( [qw/single double/] ), default => 'single' } );
}

=head2 getter_params

Return list of validation parameters which shell be used in all query
operations, eg. timeout, read_length, ....

=cut

sub getter_params {
    return ( timeout_param(), read_length_param() );
}

=head2 setter_params

Return list of validation parameters which shell be used in all write
operations, eg. timeout, ....

=cut

sub setter_params {
    return ( timeout_param() );
}

sub validated_hash_no_cache {
    return validated_hash( @_, MX_PARAMS_VALIDATE_NO_CACHE => 1 );
}

=head2 validated_getter

 my ($self, %args) = validated_getter(\@_, %additional_parameter_spec);

Call C<validated_hash> with the getter_params.

=cut

sub validated_getter {
    my $args_ref                  = shift;
    my %additional_parameter_spec = @_;
    return validated_hash_no_cache(
        $args_ref, getter_params(),
        %additional_parameter_spec
    );
}

=head2 validated_setter

 my ($self, $value, %args) = validated_setter(\@_, %additional_parameter_spec);

Call C<validated_hash> with the C<setter_params> and a mandatory 'value'
argument, which must be of 'Str' type.

=cut

sub validated_setter {
    my $args_ref                  = shift;
    my %additional_parameter_spec = @_;
    my ( $self, %args ) = validated_hash_no_cache(
        $args_ref, setter_params(),
        value => { isa => 'Str' }, %additional_parameter_spec
    );
    my $value = delete $args{value};
    return ( $self, $value, %args );
}

=head2 validated_no_param_setter

 my ($self, %args) = validated_no_param_setter(\@_, %additional_parameter_spec);

Like C<validated_setter> without the 'value' argument.

=cut

sub validated_no_param_setter {
    my $args_ref                  = shift;
    my %additional_parameter_spec = @_;
    my ( $self, %args ) = validated_hash_no_cache(
        $args_ref, setter_params(),
        %additional_parameter_spec
    );
    return ( $self, %args );
}

sub get_default_channel {
    my $self = shift;
    if ( $self->can('instrument_nselect') ) {
        my $channel = $self->cached_instrument_nselect();
        return $channel == 1 ? '' : $channel;
    }
    else {
        return '';
    }
}

=head2 validated_channel_getter

 my ($self, $channel, %args) = validated_channel_getter(\@_);

Like C<validated_getter> with an additional C<channel_param> argument. If the
no channel argument is given, try to call
C<$self->cached_instrument_nselect>. If this method is not available, return
the empty string for the channel.

=cut

sub validated_channel_getter {
    my $args_ref                  = shift;
    my %additional_parameter_spec = @_;
    my ( $self, %args ) = validated_hash_no_cache(
        $args_ref,       getter_params(),
        channel_param(), %additional_parameter_spec
    );

    my $channel = delete $args{channel};
    if ( not defined $channel ) {
        $channel = $self->get_default_channel();
    }
    return ( $self, $channel, %args );
}

=head2 validated_channel_setter

 my ($self, $channel, $value, %args) = validated_channel_setter(\@_);

Analog to C<validated_channel_getter>.

=cut

sub validated_channel_setter {
    my $args_ref                  = shift;
    my %additional_parameter_spec = @_;
    my ( $self, %args ) = validated_hash_no_cache(
        $args_ref, getter_params(), channel_param(),
        value => { isa => 'Str' },
        %additional_parameter_spec,
    );
    my $channel = delete $args{channel};
    if ( not defined $channel ) {
        $channel = $self->get_default_channel();
    }
    my $value = delete $args{value};
    return ( $self, $channel, $value, %args );
}

__PACKAGE__->meta->make_immutable();

1;
