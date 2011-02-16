#!/usr/bin/perl -w
# POD

#
# MODBUS connection driver.
# The MODBUS standard defines a protocol to access the memory of connected devices,
# possible interfaces are RS485/RS232 and Ethernet.
# For now this driver uses Lab::Connection::RS232 as backend. It's main use is to
# generate the checksums used by MODBUS RTU. The memory addresses are device specific and
# have to be stored in the according Instrument packages.
#

use strict;

package Lab::Connection::MODBUS_RS232;
use Lab::Connection::RS232;
use Carp;
use Data::Dumper;

use threads;
use Thread::Semaphore;


# setup this variable to add inherited functions later
our @ISA = ("Lab::Connection::RS232");

our $VERSION = sprintf("1.%04d", q$Revision: 713 $ =~ / (\d+) /);

our $INS_DEBUG=0; # do we need additional output?

my @crctab = ();

my $ConnSemaphore = Thread::Semaphore->new();	# a semaphore to prevent simultaneous use of the connection by multiple threads

my %fields = (
	crc_init => 0xFFFF,
 	crc_poly => 0xA001,
	MaxCrcErrors => 3,
);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	#my %args = @_;
	my $args = shift;
	my $self = $class->SUPER::new($args); # getting fields and _permitted from parent class
	foreach my $element (keys %fields) {
		$self->{_permitted}->{$element} = $fields{$element};
	}
	@{$self}{keys %fields} = values %fields;

	$self->_crc_inittab(); #Precalculations for checksum generation

	return $self;
}



sub InstrumentNew { # $self=Connection, { SlaveAddress => Device address (1byte) }
	my $self = shift;
	# get arguments
	my %args = @_;
	my $SlaveAddress;

	if ( exists $args{'SlaveAddress'} && $args{'SlaveAddress'} =~ /[0-9]*/ && $args{'SlaveAddress'} > 0 && $args{'SlaveAddress'} < 255 ) {
		$SlaveAddress = $args{'SlaveAddress'};
	}
	else { croak('No or invalid MODBUS Slave Address given. I can\'t work like this!'); }

	my $Instrument=  { valid => 1, type => "MODBUS", SlaveAddress => $SlaveAddress };  
	return $Instrument;
}



sub InstrumentRead { # $self=Connection, \%InstrumentHandle, \%Options = { Function, MemAddress, MemCount }
	use bytes;
	my $self = shift;
	my $Instrument=shift;
	my $Options = shift;
	my $Function = int($Options->{'Function'}) || undef;
	my $MemAddress = int($Options->{'MemAddress'}) || undef;
	my $MemCount = int($Options->{'MemCount'}) || 1;
	my @Result = ();
	my $Success = 0;
	my $ErrCount = 0;
	my $Message = "";
	my @MessageArr = ();
	my @AnswerArr = ();
	my @TmpArr = ();

	croak('Undefined or unimplemented Function') if(!defined $Function || $Function != 3);
	croak('Invalid Memory Address') if(!defined $MemAddress || $MemAddress < 0 || $MemAddress > 0xFFFF );

	@MessageArr = $self->_MB_CRC( $Instrument->{SlaveAddress}, $Function, (int($MemAddress) & 0xFF00) >> 8, int($MemAddress) & 0x00FF, (int($MemCount) & 0xFF00) >> 8, int($MemCount) & 0x00FF );

	foreach my $item (@MessageArr) {
		$Message .= chr($item);
	}

	$Success=0;
	$ErrCount=0;
	$self->ConnSemaphore->down();
	do {
		$self->WriteRaw($Message);
		@AnswerArr = split(//, $self->Read('all'));
		for my $item (@AnswerArr) { $item = ord($item) }
		@TmpArr = $self->_MB_CRC(@AnswerArr);
		if ($TmpArr[-2] + $TmpArr[-1] != 0) {	# CRC over the message including its correct CRC results in a "CRC" of zero
			$ErrCount++;
			$ErrCount < $self->MaxCrcErrors() ? warn "Error in MODBUS response - retrying\n" : warn "Error in MODBUS response\n";
		}
		else {
			warn "...Success\n" if $ErrCount > 0;
			$Success=1;
		}
	} until($Success==1 || $ErrCount >= $self->MaxCrcErrors());
	$self->ConnSemaphore->up();
	warn "Too CRC many errors, giving up after ${\$self->MaxCrcErrors()} times.\n" unless $Success;
	return undef unless $Success;

	# formally correct - check response
	if( scalar(@AnswerArr) == 5 ) { # Error answer received?
		$Success=0;
		# Now: warn and tell error code. Later: throw exception
		warn "Received MODBUS error message with error code $AnswerArr[2] \n";
	}
	elsif( scalar(@AnswerArr) < $AnswerArr[2] + 5 ) { # correct message length? carries all bytes it says it does?
		$Success=0;
	}

	if($Success==1) {	# read result, as an array of bytes
		for my $item (@AnswerArr[3 .. 3+$AnswerArr[2]-1]) {
			push(@Result, $item);
		}
		return @Result;
	}
	else {
		return undef;
	}
}


sub InstrumentWrite { # $self=Connection, \%InstrumentHandle, \%Options = { Function, MemAddress, MemValue }
	use bytes;
	my $self = shift;
	my $Instrument=shift;
	my $Options = shift;
	my $Function = int($Options->{'Function'}) || undef;
	my $MemAddress = int($Options->{'MemAddress'}) || undef;
	my $MemValue = int($Options->{'MemValue'});
	my $Result = undef;
	my $Message = "";
	my @MessageArr = ();
	my $Success = 0;
	my @AnswerArr;
	my @TmpArr = ();
	my $ErrCount=3;

	if(!defined $Function || $Function != 6) 								{ warn("Undefined or unimplemented MODBUS Function\n"); return undef; }
	if(!defined $MemAddress || $MemAddress < 0 || $MemAddress > 0xFFFF ) 	{ warn("Invalid Memory Address $MemAddress\n"); return undef; }
	if(!defined $MemValue || $MemValue < 0 || $MemValue > 0xFFFF ) 			{ warn("Invalid Memory Value $MemValue\n"); return undef; }

	@MessageArr = $self->_MB_CRC( $Instrument->{SlaveAddress}, $Function, (int($MemAddress) & 0xFF00) >> 8, int($MemAddress) & 0x00FF, (int($MemValue) & 0xFF00) >> 8, int($MemValue) & 0x00FF);
	foreach my $item (@MessageArr) {
		$Message .= chr($item);
	}

	$Success=0;
	$ErrCount=0;
	$self->ConnSemaphore->down();
	do {
		$self->WriteRaw($Message);
		@AnswerArr = split(//, $self->Read('all'));
		for my $item (@AnswerArr) { $item = ord($item) }
		@TmpArr = $self->_MB_CRC(@AnswerArr);
		if ($TmpArr[-2] + $TmpArr[-1] != 0) {	# CRC over the message including its correct CRC results in a "CRC" of zero
			$ErrCount++;
			$ErrCount < $self->MaxCrcErrors() ? warn "Error in MODBUS response - retrying\n" : warn "Error in MODBUS response\n";
		}
		else {
			warn "...Success\n" if $ErrCount > 0;
			$Success=1;
		}
	} until($Success==1 || $ErrCount >= $self->MaxCrcErrors());
	$self->ConnSemaphore->up();
	warn "Too many CRC errors, giving up after ${\$self->MaxCrcErrors()} times.\n" unless $Success;
	return undef unless $Success;

	# formally correct - check response;
	$Success = 1;
	if( scalar(@AnswerArr) == 5 ) { # Error answer received? Error answers are 5 bytes long.
		$Success=0;
		# Now: warn and tell error code. Later: throw exception
		warn "Received MODBUS error message with error code $AnswerArr[2] \n";
	}
	if($Success==1) {
		# compare sent message and answer. equality signals success.
		for(my $i=0; $i < scalar(@AnswerArr); $i++) {
			if( $AnswerArr[$i] ne $MessageArr[$i] ) {
				$Success = 0;
				$i=scalar(@AnswerArr);
			}
		}
	}

	return $Success;
}



sub _crc_inittab () {
	my $self = shift;
	my $crc=0;
	my $c=0;
	my $i=0;
	my $j=0;

	my $crc_poly=$self->crc_poly();

	for ($i=0; $i<256; $i++) {
		$crc=0;
		$c = $i;
	
		for ($j=0; $j<8; $j++) {

		if ( ($crc ^ $c) & 0x0001 ) { $crc = ($crc >> 1 ) ^ $crc_poly }
		else { $crc = ( $crc >> 1 ) }

		$c = ( $c >> 1 );
		}

		$crctab[$i] = $crc;
	}
}


# generate MODBUS CRC for given message
sub _MB_CRC { # @Message
	my $self = shift;
	my @message = @_;
	_crc_inittab() if(!@crctab);

	my $crc_poly=$self->crc_poly();
	my $crc_init=$self->crc_init();


	my $size = @message;
	my $remainder=$crc_init;
	my $tmp = 0;
	my $i=0;

	for($i=0; $i<$size; $i++) {
		$tmp = $remainder ^ ( 0x00ff & $message[$i] );
		$remainder = ( $remainder >> 8 ) ^$crctab[$tmp & 0xff];
	}

	return ( @message, $remainder & 0x00FF, ($remainder & 0xFF00) >> 8 );
}


1;


=head1 NAME

Lab::Connection::MODBUS_RS232 - Perl extension for interfacing with instruments via RS232/RS485 using the MODBUS RTU protocol

=head1 SYNOPSIS

  use Lab::Connection::MODBUS_RS232;
  my $h = Lab::Connection::MODBUS_RS232->new( Interface 		=> 'RS232',
				                			Port			=> 'COM1|/dev/ttyUSB1'
											SlaveAddress	=> '1');


=head1 DESCRIPTION

This is an interface package for Lab::Instruments to communicate via RS232/RS485 with a MODBUS RTU enabled device.
It uses Lab::Connection::RS232 (RS485 can be done using a RS232<->RS485 converter for now). It's main use is to calculate the
checksums needed by MODBUS RTU.

Refer to your device for the correct port configuration.

=head1 CONSTRUCTOR

=head2 new

All parameters are used as by C<Device::SerialPort> respectively C<Lab::Connection::RS232>.
Port is needed in every case. Default value for timeout is 500ms and can be set by the parameter "Timeout".
Other options you probably have to set: Handshake, Baudrate, Databits, Stopbits and Parity.

=head1 METHODS

Used by C<Lab::Instrument>. Not for direct use!!!

=head2 InstrumentRead

Reads data. Arguments:
Function (0x01,0x02,0x03,0x04 - "Read Coils", "Read Discrete Inputs", "Read Holding Registers", "Read Input Registers")
SlaveAddress (0xFF)
MemAddress ( 0xFFFF, Address of first word )
MemCount ( 0xFFFF, Count of words to read )


=head2 Write

Send data to instrument. Arguments: 
Function (0x05,0x06,0x0F,0x10 - "Write Single Coil", "Write Single Register", "Write Multiple Coils", "Write Multiple Registers")
Currently only 0x06 is implemented.
SlaveAddress (0xFF)
MemAddress ( 0xFFFF, Address of word )
Value ( 0xFFFF, value to write to MemAddress )


=head1 CAVEATS/BUGS

This is a prototype...

=head1 SEE ALSO

=over 4

=item L<Lab::Connection>

=item L<Lab::Connection::RS232>

=item L<Lab::Instrument>

=item L<Win32::SerialPort>

=item L<Device::SerialPort>

=back

=head1 AUTHOR/COPYRIGHT

Florian Olbrich 2010

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut