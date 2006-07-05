package Sendpage::Recipient;

# this package will encapsulate the data of a single recipient
#
# $Id$
#
# Copyright (C) 2000-2004 Kees Cook
# kees@outflux.net, http://outflux.net/
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# <URL:http://www.gnu.org/copyleft/gpl.html>

=head1 NAME

Sendpage::Recipient - encapsulates the data of a single recipient

=head1 SYNOPSIS

 $recip = Sendpage::Recipient->new($config, $db, $name, $data);
 $alias = $recip->alias();
 @dests = @{ $recip->dests() };
 @data  = @{ $recip->data() };
 $value = $recip->datum("field");
 $pin   = $recip->pin();
 $pc    = $recip->pc();
 $name  = $recip->name();

=head1 DESCRIPTION

This module is used internally by L<sendpage> to encapsulate data for a
single recipient.

=cut

sub new
{
    # spec for data mapping
    my @RecipSpec = qw(email-cc);

    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = { };

    $self->{CONFIG} = shift;		# configuration
    my $db	    = shift;		# db info, if using a db
    my $name	    = shift;		# our look-up name
    my $data	    = shift;		# ref to hash of misc info
    my @list;

    # who are all our destinations?
    my $list  = $self->{CONFIG}->get("recip:${name}\@dest", 1);
    if (!defined($list) && $name !~ /\@/) {
	# try looking in the db if it is in use
	if ($db) {
	    #warn "db check ${name} dest\n";
	    @list = $db->check("${name}:dest");
	}
	$list = { @list };
	unless (defined $list) {
	    $main::log->do('debug', "No such recipient: '%s'", $name)
		if $self->{CONFIG}->get("alias-debug");
	    return undef;
	}
    } else {
	@list = @{ $list };
    }

    #warn "DESTS:\n";
    #my $cow;
    #foreach $cow (@list) {
    #	warn "dest: $cow\n";
    #}
    #warn "--end-($#list)\n";

    # do we exist at all?
    if (!defined($list) || $#list < 0) {
	# if we don't exist as a valid "alias" with options,
	# then we should allow expansion if we contain "@",
	# and a valid PC identifier

	if ($name =~ /\@/) {
	    my @parts = split(/\@/, $name, 2);

	    ($self->{PIN}, $self->{PC}) = @parts[0,1];
	    # verify that we have a legit PC
	    unless ($self->{CONFIG}->instance_exists("pc:" . $self->{PC})) {
		$main::log->do('warning',
			       "no such PC '%s' defined for '%s'!",
			       $self->{PC}, $self->{PIN});
		return undef;
	    }
	    # build up the destination "list"
	    undef @list;
	    push @list, $name;
	    $list = \@list;
	} else {
	    return undef;
	}
    }
    # are we a single entity, that isn't an alias?
    elsif ($#list == 0
	   && ($list[0] =~ /\@/
	       || !$self->{CONFIG}->instance_exists("recip:" . $list[0]))) {

	# we are at the end of the line
	$self->{ALIAS} = 0;

	my @parts = split(/\@/, $list[0], 2);

	($self->{PIN}, $self->{PC}) = @parts[0,1];
	# verify that we have a legit PC
	unless ($self->{CONFIG}->instance_exists("pc:" . $self->{PC})) {
	    $main::log->do('warning',
			   "no such PC '%s' defined for '%s'!",
			   $self->{PC}, $self->{PIN});
	    return undef;
	}
    } else {
	$self->{ALIAS} = 1;
    }
    $self->{DEST} = $list;
    $self->{DATA} = ( );

    # handle passing generics down to recipient
    foreach my $thing (@RecipSpec) {
	# FIXME: clean this up
	my($generic, $datum);
	undef $generic;
	# first, get generic from passed in variables
	$generic = $data->{$thing} if defined($data->{$thing});
	# next, get from specific recip entry if it exists
	$datum = $self->{CONFIG}->get("recip:${name}\@${thing}", 1);
	if (defined($datum) || defined($generic)) {
	    $self->{DATA}->{$thing} = defined($datum) ?
		$datum : $generic;
	    #printf "datum '%s' is '%s'\n",
	    #	$thing,
	    #	$self->{DATA}->{$thing};
	}
    }

    $self->{NAME} = $name;

    #warn "Recipient '$name' built\n";

    return bless $self => $class;;
}

# Pure accessor methods, no modifying of object attributes
foreach my $field (qw(alias dests data pin pc name)) {
    no strict "refs";		# Access symbol table
    *$field = sub
    {
	my $self = shift;
	return $self->{uc $field};
    };
}

sub datum
{
    my ($self, $want) = @_;

    $self->{DATA}->{$want};
}

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 BUGS

Need to write more docs.

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::Modem>, L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>,
L<Sendpage::Page>, L<Sendpage::Queue>.

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
