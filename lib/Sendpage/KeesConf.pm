#
# KeesConf.pm implements a quick-and-dirty configfile parser
#
# $Id$
#
# Copyright (C) 2000 Cornelius Cook
# cook@cpoint.net, http://collective.cpoint.net/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

package Sendpage::KeesConf;
use Carp;

=head1 NAME

Sendpage::KeesConf - implements a configuration file reader

=head1 SYNOPSIS

    use Sendpage::KeesConf;
    $config = Sendpage::KeesConf->new();

    $config->define("variable", { DEFAULT => "setting" });

    $config->file("config.cfg");

    $setting=$config->get("variable");

=head1 DESCRIPTION

I have borrowed VERY heavily from Andy Wardley's (abw@cre.canon.co.uk)
C<AppConfig> tool, which can be found on CPAN (http://cpan.perl.org)
but I found it not dynamic enough for multi-instance variable defaults.
As a result, I wrote this massively trimmed-down version for my use.

The following methods are available:

=over 4

=cut

# off-limits chars in section names are    : @ =
#
# -Kees

# argument count types
$ARGCOUNT_NONE  = 0;
$ARGCOUNT_ONE   = 1;
$ARGCOUNT_LIST  = 2;
#$ARGCOUNT_HASH  = 3;

=item $config = Sendpage::KeesConf->new();

The constructor doesn't take an arguement, but it should in the future.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
        my $self = {};

        # get our args
        my $config = shift;

	$self->{DEFAULTS} = undef;
	$self->{KNOWN} = undef;

	bless($self,$class);
	return $self;
}

=item $config->forget();

This call will make $config forget about any variables it has loaded.
It does NOT forget C<define>d variables, just instantiated ones via C<file>.

=cut

# forget all configurations
sub dump {
	my $self = shift;
	$self->{KNOWN} = undef;
	$self->{SECTIONS} = undef;
}

=item $config->define($name, $options);

This will define a variable by the name of $name.

$options can contain:

=over 4

=item ARGCOUNT 

What type of variable this should.  Default value is "1".  The available
types are:

=over 4

=item 0

Boolean (true/false, yes/no, 1/0)

=item 1

Scalar (any string)

=item 2

List (an array of strings)

=back

=item DEFAULT

The default value the variable should have if it is not overridden during
the call to C<file>.  The DEFAULT must be the same data type as ARGCOUNT.
The default DEFAULT is "<unset>".

=item UNSET

set this to 1 if you want the default value to be undefined.  This is
a hack to get around the default DEFAULT.

=back

=cut

# define a variable
sub define {
	my $self = shift;
	my ($name, $vars)=@_;

	my $default;

	$self->{DEFAULTS}->{$name}->{ARGCOUNT}=defined($vars->{ARGCOUNT}) ?
		$vars->{ARGCOUNT} : $ARGCOUNT_ONE;
	if ($self->{DEFAULTS}->{$name}->{ARGCOUNT} == $ARGCOUNT_LIST) {
		$self->{DEFAULTS}->{$name}->{DEFAULT}= defined($vars->{DEFAULT}) ?
			$vars->{DEFAULT} : undef ;
	}
	else {
		$self->{DEFAULTS}->{$name}->{DEFAULT}= defined($vars->{DEFAULT}) ?
			$vars->{DEFAULT} : "<unset>";
	}

	undef $self->{DEFAULTS}->{$name}->{DEFAULT} if (defined($vars->{UNSET}));

	#warn "'$name' defined with '".$self->{DEFAULTS}->{$name}->{ARGCOUNT}."' and '".$self->{DEFAULTS}->{$name}->{DEFAULT}."'\n";
	
}

=item $config->instance_exists($name);

This tests to see if there is a section loaded named $name

=cut

# check to see if a section exists in the KNOWN space
sub instance_exists {
	my ($self,$name)=@_;

	#warn "\tchecking for instance: '$name'\n";

	my(%hash, $thing);

	foreach $thing (@{ $self->{SECTIONS} }) {
		$hash{$thing}=1;
		#warn "\t\tI have: '$thing'\n";
	}

	return defined($hash{$name});
}

=item $var=$config->get($name);

This call will search for the variable named $name.  If it is not found,
it will fall back to the default for the section.   Sections are explained
in more detail later.

=cut

# return a variable or default for that variable
sub get {
	my $self = shift;
	my ($whole,$quiet)=@_;
	my ($name,$class,$instance,$var,@parts);

	# Vars can be in CLASS:Instance@variable format
	# knowns use the entire name,
	# defaults use CLASS:variable format

	undef $name;
	#warn "asking for '$whole'\n";

	$value=$self->{KNOWN}->{$whole};

	if (!defined($value)) {
		# save our original value
		$name=$whole;

		($class,$instance,$name)=$self->breakdown($name);

		# reduce our variable to just class/var
		$whole=sprintf("%s$name",$class ? "$class:" : "");

		#warn "getting default for '$whole'\n";
		my $def=$self->{DEFAULTS}->{$whole};
		if (!defined($def) && $class) {
			$def=$self->{DEFAULTS}->{"$class:"};
		}
		if (defined($def)) {
			# getting classed default
			#warn "found default for '$whole'\n";
			$value=$def->{DEFAULT};
		}
	}

	if (!defined($value) && !$quiet) {
		croak "'$whole' not defined";
	}

	return $value;
}

=item $config->instances($class);

Returns an array of the names of all the variables in the class $class.

=cut

sub instances {
	my $self = shift;
	my($class)=@_;
	my @array=sort @{ $self->{SECTIONS} };

	grep(s/^${class}://, @array);
}

=item $config->file('program.cfg');

Loads variables from the named file.  Syntax for this file is:

    [SECTION:INSTANCE]
    VARIABLE1 = VALUE1
    VARIABLE2 = VALUE2
    .
    .
    .

If VARIABLE is an array, VALUE is loaded using commas (,) as the
list separator.  The variable will be available under the name of the
section.  For example, to see VALUE2, it would be accessed as:

    $config->get("SECTION:INSTANCE\@VARIABLE2");

Notice, that "=", ":", and "@" are all not allowed in section or
variable names.

=cut

# load variables from a file
sub file {
	my $self=shift;
	my $filename=shift;
	my (@lines,@merged,$line);

	# for parsing, I prefer this methodology:
	#	1) strip all lines starting with a "#"
	#	2) join any lines that have a "\" as the last character
	#	3) drop any blank lines
	#	4) parse, one line at a time

	open(FILE,"<$filename") || die "Cannot read '$filename'\n";
	@lines=grep(!/^#/,<FILE>);	# drop any lines starting with #
	close(FILE);

	# merge any line with a trailing \
	undef @merged;
	undef $line;
	while ($#lines>=0) {
		$line=shift @lines;
		chomp($line);	# drop crs
		while ($line =~ /\\$/ && $#lines>=0) {
			$line.=shift @lines;
		}
		push(@merged,$line);
		undef $line;
	}

	@lines=grep(!/^\s*$/,@merged);	# drop any blank lines

	my $section="";

	foreach $line (@lines) {
		#warn "saw line '$line'\n";
		my ($token,$value)=split(/=/,$line,2);

		# drop any white-space surrounding the token
		$token=~s/^\s*//;
		$token=~s/\s*$//;

		if ($token =~ /^\[([^\]]+)\]/) {
			$section=$1;
			# drop any white-space surrounding the section
			$section=~s/^\s*//;
			$section=~s/\s*$//;
			# clean up section name (no @s)
			$section=~s/\@//g;

			#warn "saw section '$section'\n";
			if ($self->instance_exists($section)) {
				$main::log->do('warning',
					"section '$section' already defined -- merging!");
			}
			else {
				push(@{ $self->{SECTIONS} },$section);
			}

			$section.="\@";

			next;
		}

		# drop any white-space surrounding the value
		$value=~s/^\s*//;
		$value=~s/\s*$//;

		# drop any quotes (not really syntax-smart, ya know?)
		$value=~s/^"//;
		$value=~s/"$//;

		# add our section header
		$token="${section}${token}";

		#warn "token: '$token' value: '$value'\n";
		# now our token/values are "clean".  Let's insert them
		# into our various structures
		
		#warn "Checking on defaults for '$token'\n";
		my ($class,$instance,$name)=$self->breakdown($token);
		#warn "got '$class' : '$instance' \@ '$name'\n";
		# reduce our variable to just class/var
		my $whole=sprintf("%s$name",$class ? "$class:" : "");

		#warn "Checking on defaults for '$whole'\n";

		my $def=$self->{DEFAULTS}->{$whole};
		if (!defined($def) && $class) {
			$def=$self->{DEFAULTS}->{"$class:"};
			#warn "tried '$class:'\n";
		}
		if (defined($def)) {
			if ($def->{ARGCOUNT} == $ARGCOUNT_NONE) {
				if ($value=~/^[ty1]/i) {
					$self->{KNOWN}->{$token}=1;
					#warn "stored '$token' as '1'\n";
				}
				elsif ($value =~ /^[fn0]/i) {
					$self->{KNOWN}->{$token}=0;
					#warn "stored '$token' as '0'\n";
				}
				else {
					$main::log->do('warning',
						"value for '$token' not true/false, yes/no, 1/0");
				}
			}
			elsif ($def->{ARGCOUNT} == $ARGCOUNT_ONE) {
				$self->{KNOWN}->{$token}=$value;
				#warn "stored '$token' as '$value'\n";
			}
			elsif ($def->{ARGCOUNT} == $ARGCOUNT_LIST) {
				#warn "adding to '$token'\n";
				my @parts=split(/[\s,]+/,$value);
				my $item;
				foreach $item (@parts) {
					# drop white space
					$item=~s/^\s*//;
					$item=~s/\s*$//;
					#warn "\t'$item'\n";
					push(@{$self->{KNOWN}->{$token}},$item);
				}
			}
			else {
				$main::log->do('warning',
					"default for '$whole' has strange ARGCOUNT");
			}
		}
		else {
			$main::log->do('warning',"unknown variable '$token' found in file '$filename'");
		}
	}

	
	return 1;
}

# "dangerous" hack to set a variable
sub set {
	my($self,$var,$value)=@_;

	$self->{KNOWN}->{$var}=$value;
}

# breakdown a variable name into class, instance, and variable
#
#	input string: "CLASS:INSTANCE@NAME" where "CLASS:" is optional
#			and "INSTANCE@" is optional
#
sub breakdown {
	my $self=shift;
	my ($name)=@_;
	my (@parts,$class,$instance);

	# strip off the class, if it exists
	@parts=split(/:/,$name,2);
	$class=$parts[0];
	if ($class eq $name) {
		undef $class;
	}
	else {
		#warn "class: '$class'\n";
		$name=$parts[1];
	}

	# strip off the instance if it exists
	@parts=split(/\@/,$name,2);
	$instance=$parts[0];
	if ($instance eq $name) {
		undef $instance;
	}
	else {
		#warn "instance: '$instance'\n";
		$name=$parts[1];
	}

	return ($class,$instance,$name);
}

1;

__END__

=back

Sections can be defined (and loaded) so that defaults can pass back 
to a defined section default.  For example, lets say that you have 
several modems, and most of them have different settings.  You can define
all the modem variables like so:

	$config->define("modem:baud",{ DEFAULT => 9600 });
	$config->define("modem:flowctl",{ DEFAULT => "hardware" });

Then, when you load them, let's say the config file has:

	[modem:sportster]
	baud = 115200

	[modem:hayes]

The baud rate for the sportster will come back as 115200, but the hayes
will fall back during a C<get> call, and find the default for the modem
section: 9600.  Both fallback to have "flowctl" as "hardware":

    # returns specific value 115200
    $config->get("modem:sportster\@baud");

    # returns default value 9600
    $config->get("modem:hayes\@baud");       

    # both return default value "hardware"
    $config->get("modem:sportster\@flowctl");
    $config->get("modem:hayes\@flowctl");   

=head1 CAVEATS

=over 4

=item character limitations

As mentioned above, variable names (and section names) cannot have the
characters ":", "@", or "=" in them.

=item default defaults

There should be a way to pass default defaults into C<new>.  That would
be handy, and could eliminate the need for the UNSET option in C<define>.

=back

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesLog(3), Sendpage::Modem(3),
Sendpage::PagingCentral(3), Sendpage::PageQueue(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

