package Lab::IO::Data::Error;

use Lab::IO::Data;
our @ISA = ('Lab::IO::Data');

# Test 1 param
package Lab::IO::Data::Error::CorruptParameter;
our @ISA = ('Lab::IO::Data::Error');
our $msg = 'Parameter %param% is of wrong type or otherwise corrupt!';

# Test 2 params
package Lab::IO::Data::Error::CorruptTwo;
our @ISA = ('Lab::IO::Data::Error');
our $msg = 'Parameters %param1% and %param2% are of wrong type or otherwise corrupt!';
